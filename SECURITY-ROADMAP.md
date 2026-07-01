# Roadmap de Segurança — redhusky-lab-01 (167.86.110.111)

> Origem: auditoria 2026-06-30. Host **não comprometido**, mas com exposição
> crítica à internet e brute-force SSH ativo. Este roadmap prioriza por risco
> real e casa com a aba **Segurança** do orchestration-redhusky.

---

## Achados da auditoria (2026-06-30)

| # | Achado | Severidade | Evidência |
|---|--------|-----------|-----------|
| 1 | SSH: root + senha habilitados, sem fail2ban, firewall off | 🔴 Crítico | `permitrootlogin yes`, `passwordauthentication yes`; milhares de tentativas/dia (`91.92.40.202` 1357×, `91.92.42.147` 1257×…) |
| 2 | Ollama `0.0.0.0:11434` sem auth | 🔴 Crítico | exposto desde 27/Jun; ~15 IPs/dia varrendo `/api/tags`, `/v1/models` |
| 3 | Redis `0.0.0.0:6380` exposto à internet ⚠️ correção: tem `requirepass`, achado original leu `NOAUTH` ao contrário (ver Fase 0) | 🟡 Médio | `docker exec redis_redis redis-cli -h <public-ip> -p 6380 ping` sem auth → `NOAUTH Authentication required` (senha exigida, não ausente) |
| 4 | Firewall desligado; Postgres/MinIO/Kafka/PgBouncer em 0.0.0.0 | 🔴 Crítico | `ufw inactive`, `iptables INPUT ACCEPT`; portas 5432/6432/9001/8082… públicas |

**Não comprometido:** só `root` UID 0; nenhum `Accepted password` externo em 7 dias;
sem miner (`kdevtmpfs` pid 89 = thread de kernel real); cron e binários legítimos.

---

## Fase 0 — Conter agora — ✅ implementado (2026-07-01)

> **Incidente:** a primeira tentativa de aplicar o passo 5 (firewall) travou a
> sessão ("3 shells still running") e o host levou 3 reboots seguidos; o
> operador perdeu acesso SSH e teve que recuperar via console de rescue
> (`chpasswd -R /mnt`). Causa mais provável: `ufw --force enable` sem a regra
> de 22 confirmada antes de um reboot aplicar o estado parcial. Por isso a
> segunda tentativa (abaixo) **evita `ufw enable`/`default deny` por completo**
> — só mexe na chain `DOCKER-USER`, que nunca intercepta a porta 22 (SSH não
> passa por FORWARD, só INPUT direto).

1. **Ollama → bind interno.** `OLLAMA_HOST=172.18.0.1` em
   `/etc/systemd/system/ollama.service.d/override.conf`, `daemon-reload` +
   `restart`. Confirmado: responde em `172.18.0.1:11434`, recusa em
   `127.0.0.1` e em qualquer outra interface.
2. **fail2ban** — já estava ativo (jail `sshd`, banaction nftables).
3. **Redis** — `requirepass` **já estava configurado** no compose
   (`~/docker/redis/docker-stack.yml`); a auditoria original leu o erro
   `NOAUTH Authentication required` como "sem senha", quando na verdade
   significa o oposto (senha exigida, request sem credencial). Nenhuma
   mudança necessária no compose — só fechar a porta 6380 (item 5).
4. **SSH hardening** — feito numa sessão anterior: `PermitRootLogin
   prohibit-password`, `PasswordAuthentication no`, key-only.
5. **Firewall** — UFW segue **inativo de propósito** (ver nota do incidente
   acima). Em vez disso: regra `DOCKER-USER` escopada, que bloqueia as portas
   sensíveis vindas da internet (`eth0`) sem tocar em SSH:
   ```bash
   iptables -I DOCKER-USER -i eth0 -p tcp -m multiport \
     --dports 5432,6432,5436,9001,8082,8404,11434,6380 -j DROP
   ```
   Persistida via `/usr/local/bin/docker-user-firewall.sh` (idempotente,
   espera a chain `DOCKER-USER` existir) + `@reboot` no crontab — iptables
   não sobrevive reboot sozinho, e essa foi provavelmente a razão da regra
   nunca ter "pegado" da primeira vez.

**Pendência:** UFW continua inativo. Se algum dia quiser ativá-lo, regra de
ouro: `ufw allow 22/tcp` (ou melhor, restringir por IP) **antes** de `ufw
enable`, nunca o inverso, e nunca seguido de reboot sem confirmar uma segunda
sessão SSH ativa primeiro.

---

## Fase 1 — Painel de exposição (✅ implementado)

Aba **Segurança** na sidebar do orchestration-redhusky.

- `app/services/security_audit.rb` — lê `/host/proc/1/net/tcp{,6}` (namespace de
  rede do host via PID 1), classifica portas em LISTEN: crítico (serviço
  sensível público) / aviso (porta pública desconhecida) / ok (22/80/443).
  Score 0–100 + contadores. Self-check em `__main__` + `test/services/security_audit_test.rb` (7 testes).
- `SecurityController#index` (`require_admin!`) + `app/views/security/index.html.erb`.
- Rota `GET /security`, link na sidebar (ícone `auth_shield`), breadcrumb.

**Escopo:** só exposição de portas — é o que o container enxerga sem privilégio
extra. Tudo já disponível via mounts atuais (`/proc:/host/proc:ro`).

---

## Fase 2 — Coletor no host (logs que o container não vê) — ✅ implementado

Container não acessa `journald`/`/var/log` nem estado de firewall. Coletor no
host grava JSON; o painel lê (read-only).

1. `/usr/local/bin/security-collect.sh` (cron `*/5 * * * *`) → escreve
   `/srv/redhusky/security/state.json`:
   - top IPs de brute-force SSH (`journalctl -u ssh`, últimas 24h)
   - logins aceitos nas últimas 24h, com timestamp, método e flag `external`
     pra IP fora das faixas privadas
   - status fail2ban (jails, contadores, IPs banidos)
   - status firewall (`ufw status` + contagem de regras `DOCKER-USER` +
     tabelas nftables presentes)
2. Bind-mount `ro` no compose (prod e dev): `/srv/redhusky/security:/host/security:ro`.
3. `SecurityAudit#host_state` lê e memoiza o JSON (`nil` se o arquivo não
   existe ainda — primeira execução do cron ou mount ausente). Novas seções
   no painel `/security`: brute-force, fail2ban, logins aceitos, firewall.
   Testes: `test/services/security_audit_test.rb` (host_state) e
   `test/controllers/security_controller_test.rb` (as duas branches da view).

**Por quê fora do app:** ler logs do host de dentro do container exigiria
`--privileged` ou montar `/var/log` + journald — superfície pior que o problema
que resolve. Coletor isolado = menor privilégio.

**Versões com CVE conhecida** (item original da Fase 2) ficou de fora —
precisa de uma fonte de CVEs pra comparar contra, escopo maior que o resto
desta fase. Fica pra Fase 4 (hardening contínuo) se algum dia for prioridade.

---

## Fase 2.5 — Integridade dos containers (`docker diff`) — ✅ implementado

Detecta malware/backdoor instalado *dentro* de um container já rodando —
`security_audit.rb` (Fase 1) só vê exposição de rede, não vê o filesystem do
container.

1. `/usr/local/bin/container-diff-collect.sh` (cron `*/15 * * * *`, cadência
   própria — `docker diff` na frota inteira sequencial estourou 3min; com
   paralelismo (`xargs -P 8`) fica em ~30s) → `docker diff` em cada container
   rodando, comparado contra a imagem original:
   - **Binários/persistência**: novo ou alterado em `/bin`, `/sbin`,
     `/usr/(local/)?s?bin`, `/etc/cron*`, `/etc/systemd`, `/etc/ld.so.preload`,
     `authorized_keys`, `/etc/passwd`, `/etc/shadow`, `/etc/sudoers`.
   - **Payload em `/tmp`, `/var/tmp`, `/dev/shm`**: qualquer arquivo novo
     **executável** nesses diretórios. Nome não importa — um incidente real
     (VPS de terceiro) mostrou o mesmo minerador reenviado a cada poucos dias
     sob nome novo (`HelloMrMeeseeks`, `virtuoso`, `batch5`...) pra escapar de
     detecção por nome; o bit de execução é o sinal real, checado via `stat`
     dentro do container só pros candidatos (não todo `docker diff`).
   - Exclui destinos de bind-mount/volume (`docker inspect .Mounts`) — isso é
     conteúdo do host, não algo instalado dentro do container.
   - Cache/log/tmp de app (`/rails/tmp/cache/bootsnap/...` etc.) não entra no
     crítico — só conta pro total, não gera ruído.
2. Escreve `/srv/redhusky/security/container-diff.json` (mesma pasta/bind-mount
   da Fase 2, `/host/security:ro` — não precisou mexer no compose).
3. `SecurityAudit#container_diff` lê e memoiza; painel `/security` ganha seção
   "Integridade dos containers", independente do `host_state` (Fase 2) —
   aparece mesmo se o coletor rápido cair. Lista só containers com achado
   crítico, com aviso de que pode ser falso positivo (ex: entrypoint que
   reescreve `/etc/passwd` pra suportar UID arbitrário — visto na prática no
   `metabase_metabase`, não confirmado como malicioso).

Testado: plantei um executável fake em `/tmp` de um container real —
detectado; arquivo não-executável no mesmo lugar — não detectado (confirma
que o filtro é o bit de execução, não o caminho).

**Ajuste pós-teste real:** a primeira versão flagrava 8 containers — todo
diretório (`hsperfdata_*` que toda JVM cria pra `jps`/`jstat`, cache dir do
Supabase edge-runtime) e socket unix (`.s.PGSQL.*` do pgbouncer) carregam bit
"x" no modo, mas não são payload. Fix: só conta arquivo regular (`stat -c %A`
começando com `-`), não diretório/socket/link. Depois do fix: só o achado real
(executável plantado) e o `metabase` (passwd/shadow, provável falso positivo
de entrypoint) sobraram.

---

## Fase 3 — Alertas e histórico

- Tabela `security_findings` (snapshot por coleta) → tendência do score no tempo.
- Disparar `Alert` (modelo existente) quando surgir novo achado crítico →
  aparece no sino de notificações.
- Opcional: webhook/n8n para Telegram em crítico.

---

## Fase 4 — Hardening contínuo

- CIS-ish: `unattended-upgrades`, SSH só-chave (já na Fase 0), `auditd`.
- Política "nunca publicar serviço sensível em 0.0.0.0" no painel de stacks
  (lint dos `ports:` no deploy — reaproveita `git_drift_service`).
- Rotação de credenciais (Redis, Postgres, JMX do Kafka — hoje `authenticate=false`).
- Cloudflare proxy + regras de origem para 80/443; resto só via VPN/WireGuard.
