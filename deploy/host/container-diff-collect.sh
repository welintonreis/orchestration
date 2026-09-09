#!/usr/bin/env bash
# RedHusky — flags filesystem drift inside running containers (docker diff
# vs image) that looks like malware/backdoor install: new or modified
# binaries in PATH dirs, cron/systemd persistence, ld.so.preload, ssh key or
# account tampering. Runs on its own (slower) cron — docker diff is too slow
# across the whole fleet to share the 5-min security-collect.sh cadence.
set -euo pipefail

OUT_DIR="/srv/redhusky/security"
OUT_FILE="${OUT_DIR}/container-diff.json"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT
mkdir -p "$OUT_DIR"

# A(dded)/C(hanged) only — deletions aren't an install. Binary dirs (backdoor
# drop or trojaned binary), persistence (cron/systemd/ld.so.preload), and
# credential/account tampering (authorized_keys, passwd, shadow, sudoers).
DANGEROUS_RE='^[AC] (/s?bin/|/usr/(local/)?s?bin/|/etc/cron|/var/spool/cron/|/etc/ld\.so\.preload|.*/\.ssh/authorized_keys|/etc/passwd$|/etc/shadow$|/etc/sudoers|/etc/systemd/|/lib/systemd/|/etc/init\.d/)'

# New files dropped in classic malware staging dirs. Naming means nothing —
# a real incident showed the same miner re-uploaded every few days under a
# rotating joke name (HelloMrMeeseeks, virtuoso, batch5...) specifically to
# dodge name-based detection. The executable bit is the actual signal, so
# these get a second pass (stat inside the container) rather than a name
# match. Capped per container so a chatty legitimate /tmp user can't blow up
# collection time.
TMP_ADD_RE='^A (/tmp/|/var/tmp/|/dev/shm/)'
TMP_CHECK_CAP=25

check_container() {
  local cid="$1" name image diff_output total candidates mount_paths critical_findings out

  name=$(docker inspect --format '{{.Name}}' "$cid" 2>/dev/null | sed 's#^/##') || return 0
  image=$(docker inspect --format '{{.Config.Image}}' "$cid" 2>/dev/null)

  diff_output=$(timeout 20 docker diff "$cid" 2>/dev/null) || true
  total=$(printf '%s\n' "$diff_output" | grep -c . || true)
  candidates=$(printf '%s\n' "$diff_output" | grep -E "$DANGEROUS_RE" || true)

  critical_findings="[]"
  if [ -n "$candidates" ]; then
    # bind/volume mount destinations always show as "added" in diff — that's
    # host-provided content, not something installed inside the container.
    mount_paths=$(docker inspect --format '{{range .Mounts}}{{.Destination}}{{"\n"}}{{end}}' "$cid" 2>/dev/null | grep -v '^$' || true)
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      local type="${line:0:1}" path="${line:2}" under_mount=false
      if [ -n "$mount_paths" ]; then
        while IFS= read -r mp; do
          case "$path" in "$mp"|"$mp"/*) under_mount=true; break ;; esac
        done <<< "$mount_paths"
      fi
      $under_mount && continue
      critical_findings=$(echo "$critical_findings" | jq --arg t "$type" --arg p "$path" '. + [{type: $t, path: $p}]')
    done <<< "$candidates"
  fi

  local tmp_candidates
  tmp_candidates=$(printf '%s\n' "$diff_output" | grep -E "$TMP_ADD_RE" | head -n "$TMP_CHECK_CAP" || true)
  if [ -n "$tmp_candidates" ]; then
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      local path="${line:2}" mode_size mode size
      mode_size=$(timeout 5 docker exec "$cid" sh -c "stat -c '%A %s' '$path'" 2>/dev/null) || continue
      [ -z "$mode_size" ] && continue
      mode="${mode_size%% *}"
      size="${mode_size##* }"
      case "$mode" in
        # leading "-" = regular file only — directories (JVM's hsperfdata_*,
        # deno/edge-runtime compile caches) and sockets (pgbouncer's
        # .s.PGSQL.*) always carry an "x" too but aren't a dropped payload.
        -*x*)
          critical_findings=$(echo "$critical_findings" | jq --arg p "$path" --arg mode "$mode" --argjson size "${size:-0}" \
            '. + [{type: "A", path: $p, executable: true, mode: $mode, size_bytes: $size}]')
          ;;
      esac
    done <<< "$tmp_candidates"
  fi

  out=$(jq -n --arg name "$name" --arg image "$image" \
    --argjson total "${total:-0}" --argjson critical "$critical_findings" \
    '{name: $name, image: $image, total_changes: $total, critical: $critical}')
  echo "$out" > "${WORK_DIR}/${cid}.json"
}
export -f check_container
export WORK_DIR DANGEROUS_RE TMP_ADD_RE TMP_CHECK_CAP

docker ps -q | xargs -r -P 8 -I{} bash -c 'check_container "$@"' _ {}

if compgen -G "${WORK_DIR}/*.json" > /dev/null; then
  containers_json=$(jq -s 'sort_by(-(.critical | length), -.total_changes)' "${WORK_DIR}"/*.json)
else
  containers_json="[]"
fi

TMP_FILE="$(mktemp "${OUT_DIR}/.container-diff.json.XXXXXX")"
jq -n --arg collected_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --argjson containers "$containers_json" \
  '{collected_at: $collected_at, containers: $containers}' > "$TMP_FILE"
chmod 644 "$TMP_FILE"
mv "$TMP_FILE" "$OUT_FILE"
