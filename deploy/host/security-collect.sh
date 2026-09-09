#!/usr/bin/env bash
# RedHusky security collector — host-side facts the orchestration container
# can't see itself (journald, fail2ban, firewall state). Writes JSON the
# panel reads read-only. See SECURITY-ROADMAP.md Fase 2.
set -euo pipefail

OUT_DIR="/srv/redhusky/security"
OUT_FILE="${OUT_DIR}/state.json"
GEOIP_CACHE="${OUT_DIR}/geoip-cache.json"
TMP_FILE="$(mktemp "${OUT_DIR}/.state.json.XXXXXX")"
trap 'rm -f "$TMP_FILE"' EXIT

mkdir -p "$OUT_DIR"
[ -f "$GEOIP_CACHE" ] || echo '{}' > "$GEOIP_CACHE"

is_private_ip() {
  case "$1" in
    127.*|10.*|172.1[6-9].*|172.2[0-9].*|172.3[0-1].*|192.168.*|::1|fc*|fd*|fe80:*) return 0 ;;
    *) return 1 ;;
  esac
}

# ── SSH brute-force: top source IPs over the last 24h ───────────────────────
brute_force_json=$(
  journalctl -u ssh --since "-24 hours" -o cat 2>/dev/null \
    | grep -E "Failed password|Invalid user|Disconnecting.*Too many authentication" \
    | grep -oE 'from [0-9]{1,3}(\.[0-9]{1,3}){3}' \
    | awk '{print $2}' \
    | sort | uniq -c | sort -rn | head -15 \
    | awk '{printf "%s %s\n", $2, $1}' \
    | jq -R -s '
        split("\n") | map(select(length > 0) | split(" ")) |
        map({ip: .[0], attempts: (.[1] | tonumber)})
      ' || true
)
# Sem match, `grep` sai 1; `pipefail` propaga mesmo com o jq tendo IMPRESSO
# `[]` com sucesso. O `|| true` acima segura o `set -e`; esta linha cobre o
# caso raro do jq falhar de verdade e não imprimir nada.
[ -n "$brute_force_json" ] || brute_force_json='[]'
total_failed=$(journalctl -u ssh --since "-24 hours" -o cat 2>/dev/null \
  | grep -cE "Failed password|Invalid user|Disconnecting.*Too many authentication" || true)

# O `|| echo '[]'` acima não é estilo: sem ele, `grep` sem match sai 1,
# `pipefail` propaga e `set -e` MATA o coletor justamente quando NÃO há
# ataque. O state.json congelava no último dia que teve tentativa, e a tela
# seguia mostrando esse ataque como se fosse das últimas 24h — foi o que
# aconteceu entre 2026-08-31 e 2026-09-09 (1 tentativa de Lima, Peru).
# Monitor que só atualiza quando há problema é pior que monitor nenhum.

# ── Geo-enrich the top IPs (cached — ip-api.com free tier, 45 req/min) ──────
geo_cache=$(cat "$GEOIP_CACHE")
for ip in $(echo "$brute_force_json" | jq -r '.[].ip'); do
  echo "$geo_cache" | jq -e --arg ip "$ip" '.[$ip]' >/dev/null 2>&1 && continue
  resp=$(curl -fsS -m 4 "http://ip-api.com/json/${ip}?fields=status,country,countryCode,city,lat,lon" 2>/dev/null) || continue
  echo "$resp" | jq -e '.status == "success"' >/dev/null 2>&1 || continue
  geo_cache=$(echo "$geo_cache" | jq --arg ip "$ip" --argjson g "$resp" '.[$ip] = {country: $g.country, country_code: $g.countryCode, city: $g.city, lat: $g.lat, lon: $g.lon}')
done
echo "$geo_cache" > "$GEOIP_CACHE"

brute_force_json=$(echo "$brute_force_json" | jq --argjson cache "$geo_cache" '
  map(. + ($cache[.ip] // {country: null, country_code: null, city: null, lat: null, lon: null}))
')

# ── Accepted logins in the last 24h, flagged if from outside private space ──
accepted_json=$(
  journalctl -u ssh --since "-24 hours" -o short-iso 2>/dev/null \
    | grep "Accepted " \
    | sed -E 's/^([0-9TZ:+.-]+) [^ ]+ sshd\[[0-9]+\]: Accepted ([a-zA-Z]+) for ([^ ]+) from ([0-9a-fA-F:.]+) port ([0-9]+).*/\1\t\2\t\3\t\4\t\5/' \
    | tail -50 \
    | jq -R -s '
        split("\n") | map(select(length > 0) | split("\t")) |
        map({time: .[0], method: .[1], user: .[2], ip: .[3], port: (.[4] | tonumber)})
      '
)
# tag external (jq has no shell access to is_private_ip, so re-flag in bash)
accepted_json=$(echo "$accepted_json" | jq -c '.[]' | while IFS= read -r row; do
  ip=$(echo "$row" | jq -r '.ip')
  if is_private_ip "$ip"; then ext=false; else ext=true; fi
  echo "$row" | jq --argjson ext "$ext" '. + {external: $ext}'
done | jq -s '.')

# ── fail2ban: jail status + banned IPs ───────────────────────────────────────
if systemctl is-active --quiet fail2ban 2>/dev/null; then
  jails=$(fail2ban-client status 2>/dev/null | awk -F'\t' '/Jail list/{print $2}' | tr ',' '\n' | sed 's/^ *//;s/ *$//' | grep -v '^$')
  fail2ban_jails_json="[]"
  for jail in $jails; do
    status=$(fail2ban-client status "$jail" 2>/dev/null)
    cur_failed=$(echo "$status" | awk -F':' '/Currently failed/{gsub(/[ \t]/,"",$2); print $2}')
    tot_failed=$(echo "$status" | awk -F':' '/Total failed/{gsub(/[ \t]/,"",$2); print $2}')
    cur_banned=$(echo "$status" | awk -F':' '/Currently banned/{gsub(/[ \t]/,"",$2); print $2}')
    tot_banned=$(echo "$status" | awk -F':' '/Total banned/{gsub(/[ \t]/,"",$2); print $2}')
    banned_ips=$(echo "$status" | awk -F':' '/Banned IP list/{print $2}' | sed 's/^[ \t]*//')
    entry=$(jq -n --arg name "$jail" \
      --argjson cur_failed "${cur_failed:-0}" --argjson tot_failed "${tot_failed:-0}" \
      --argjson cur_banned "${cur_banned:-0}" --argjson tot_banned "${tot_banned:-0}" \
      --arg banned_ips "$banned_ips" \
      '{name: $name, currently_failed: $cur_failed, total_failed: $tot_failed,
        currently_banned: $cur_banned, total_banned: $tot_banned,
        banned_ips: ($banned_ips | split(" ") | map(select(length > 0)))}')
    fail2ban_jails_json=$(echo "$fail2ban_jails_json" | jq --argjson e "$entry" '. + [$e]')
  done
  fail2ban_json=$(jq -n --argjson jails "$fail2ban_jails_json" '{running: true, jails: $jails}')
else
  fail2ban_json='{"running": false, "jails": []}'
fi

# ── Firewall: ufw + whether the DOCKER-USER drop rules from Fase 0 exist ────
ufw_active=$(ufw status 2>/dev/null | grep -q "Status: active" && echo true || echo false)
docker_user_rule_count=$(iptables -L DOCKER-USER -n 2>/dev/null | tail -n +3 | grep -cv '^$' || true)
nft_tables_json=$(nft -j list tables 2>/dev/null | jq '[.nftables[] | select(.table) | .table | "\(.family) \(.name)"]' || echo "[]")

firewall_json=$(jq -n \
  --argjson ufw_active "$ufw_active" \
  --argjson docker_user_rules "${docker_user_rule_count:-0}" \
  --argjson nft_tables "$nft_tables_json" \
  '{ufw_active: $ufw_active, docker_user_drop_rules: $docker_user_rules, nft_tables: $nft_tables}')

# ── Assemble ──────────────────────────────────────────────────────────────────
jq -n \
  --arg collected_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --argjson total_failed "${total_failed:-0}" \
  --argjson brute_force "$brute_force_json" \
  --argjson accepted_logins "$accepted_json" \
  --argjson fail2ban "$fail2ban_json" \
  --argjson firewall "$firewall_json" \
  '{
    collected_at: $collected_at,
    ssh_brute_force: { window_hours: 24, total_failed_attempts: $total_failed, top_ips: $brute_force },
    accepted_logins: $accepted_logins,
    fail2ban: $fail2ban,
    firewall: $firewall
  }' > "$TMP_FILE"

chmod 644 "$TMP_FILE"
mv "$TMP_FILE" "$OUT_FILE"
