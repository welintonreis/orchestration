# Auditoria de Infraestrutura — redhusky-lab-01

**Host:** 167.86.110.111 · Ubuntu 24.04.4 LTS · Docker 29.6.2 (Swarm leader, nó único)
**Data:** 2026-08-13 · **Modo:** somente leitura
**Recursos:** 12 vCPU · 47 GiB RAM (14 GiB em uso) · disco 387 GB, **67% usado (256 GB)** · uptime 43 dias

> Segredos encontrados durante a auditoria **não** aparecem neste documento. Onde há evidência,
> o valor está mascarado (`***`) e só o nome da variável / arquivo é citado.

---

> **Estado em 2026-08-13, fim do dia** — corrigidos nesta sessão:
> **A1** (Studio agora exige basicAuth `auth@file`; verificado de fora: 401),
> **A6** (huskyos-prod aponta para `postgres-master`/`postgres-read` pela
> overlay, não mais para a porta pública),
> **A3** (linha `0.0.0.0/0` fora do `pg_hba`; regras em IPv4 **e** IPv6, em
> `DOCKER-USER` **e** `INPUT` — o `docker-proxy` atende em userspace, caminho
> que o DOCKER-USER não vê; persistência migrada de `@reboot` para systemd
> unit `After=docker.service`; confirmado de fora que 5432 dá timeout),
> **A5** (backup diário de todos os bancos + repositórios git para o R2 —
> projeto `~/docker/redhusky-backup`, cron 04:00).
>
> **A2 fica com o Welinton** (rotação de tokens). Seguem abertos: A4, A7–A13.

## 1. Inventário de serviços

31 stacks, 65 serviços declarados. **37 rodando · 4 com falha (0/1) · 24 desligados (0/0).**

### 1.1 Serviços ativos

| Serviço | Imagem:tag | Rép. | Portas publicadas | HC | Limites CPU/Mem | Rodando há |
|---|---|---|---|---|---|---|
| `traefik_traefik` | traefik:v3.6.2 | 1/1 | 80, 443, 1433, 8082 (ingress) | – | – | 9 d |
| `postgres_postgres-master` | redhusky-postgres-walg:pg17-v2 | 1/1 | **5432** (ingress) | ✔ | – | 2 sem |
| `postgres_postgres-read` | pgvector/pgvector:pg17 | 1/1 | – | ✔ | – | 2 sem |
| `postgres_postgres-analytics` | pgvector/pgvector:pg17 | 1/1 | – | ✔ | – | 2 sem |
| `postgres_pgbouncer` | edoburu/pgbouncer:v1.24.1-p0 | 1/1 | 6432 (ingress) | – | 0.5 / 512 MB | 2 sem |
| `postgres_haproxy` | haproxy:3.1.8 | 1/1 | 5436, 8404 (ingress) | ✔ | 0.5 / 512 MB | 2 sem |
| `githusky` | githusky:v1.5.139 | 1/1 | **2223→22** (host) | – | – | 10 min |
| `githusky-runner_runner` | githusky-runner:v0.3.0 | 1/1 | – | – | – | 2 sem |
| `huskyos-prod_web` | huskyos-prod:v1.22.1 | 1/1 | – | ✔ | – | 3 d |
| `huskyos-prod_worker` | huskyos-prod:v1.22.1 | 1/1 | – | – | – | 3 d |
| `tera-brain_web` | tera-brain:v0.1.91 | 1/1 | – | – | – | 13 d |
| `tera-brain_worker` | tera-brain:v0.1.91 | 1/1 | – | – | – | 13 d |
| `husky-brs_web` | husky-brs:v0.1.49 | 1/1 | – | ✔ | 1.5 / 1 GB | 4 d |
| `huskydataops_web` | huskydataops:v0.8.16 | 1/1 | – | – | – | 7 d |
| `orchestration-prod_web` | redhusk/orchestration:v0.9.24 | 1/1 | – | – | – | 9 d |
| `redhusky-ssh_web` | redhusky-ssh:v0.1.68 | 1/1 | – | ✔ | 1 / 1 GB | 26 h |
| `redhusky-ssh_worker` | redhusky-ssh:v0.1.68 | 1/1 | – | ✔ | 0.5 / 512 MB | 11 d |
| `huskygate_provider` | huskygate:v0.1.1 | 1/1 | **4416** (ingress) | – | – | 12 d |
| `mssql_mssql` | mssql/server:2022-CU14-ubuntu-22.04 | 1/1 | – (via Traefik :1433) | ✔ | – | 9 d |
| `metabase_metabase` | metabase/metabase:v0.51.4 | 1/1 | – | – | – | 2 sem |
| `minio_minio` | minio:RELEASE.2025-04-22 | 1/1 | – | – | – | 2 sem |
| `redis_redis` | redis:8.0.1-bookworm | 1/1 | **6380→6379** (host) | ✔ | – | 2 sem |
| `supabase_*` (12 serviços) | ver §1.4 | 12/12 | – | parcial | – | 2 sem |

### 1.2 Serviços com falha (desejado 1, rodando 0) — **quebrados, não desligados**

| Serviço | Imagem | Erro | Desde |
|---|---|---|---|
| `postgres_pgadmin` | dpage/pgadmin4:**latest** | `failed to find a load balancer IP to use for network` | 2 semanas |
| `consigaz_app` | consigaz-ai:1.2.0 | `No such image: consigaz-ai:1.2.0` | 7 semanas |
| `evolution_evolution-api` | evoapicloud/evolution-api:**latest** | `task: non-zero exit (255)` | 2 semanas |
| `okane_okane-financas` | node:24-bullseye | `task: non-zero exit (1)` | 2 meses |

O Swarm segue tentando reagendar essas tarefas indefinidamente. `consigaz.redhusky.com.br` tem rota
e certificado válido, mas a imagem **não existe** no host — nunca vai subir.

### 1.3 Serviços desligados (0/0) — auditados em §6

`archimedes_web/worker/mt5_adapter` · `arpereira_adv_{web,worker,database,whatsapp,workflow}` ·
`bueno_{web,worker,bueno-pg}` · `documenso_web` · `gitlab_gitlab` · `jupyter_pyspark` ·
`kafka_{kafka,zookeeper,kafka-connect,kafka-ui,schema-registry}` · `orchestration-dev_web` ·
`paperclip_{db,server}` · `plat-redhusky_nextjs` · `plataforma_nextjs` · `rabbitmq_rabbitmq` ·
`red-closet_web` · `teste-redhusky_nextjs`

### 1.4 Violações da regra "nunca `:latest`"

| Serviço | Imagem | Réplicas | Situação |
|---|---|---|---|
| `supabase_studio` | supabase/studio:**latest** | **1/1 rodando** | 🔴 e exposto sem auth (Achado 1) |
| `postgres_pgadmin` | dpage/pgadmin4:**latest** | 0/1 (falhando) | painel de banco |
| `evolution_evolution-api` | evoapicloud/evolution-api:**latest** | 0/1 (falhando) | |
| `arpereira_adv_whatsapp` | evoapicloud/evolution-api:**latest** | 0/0 | |
| `arpereira_adv_workflow` | n8nio/n8n:**latest** | 0/0 | |
| `jupyter_pyspark` | jupyter/pyspark-notebook:**latest** | 0/0 | |

Também sem versão semântica real: `paperclip_server` → `paperclip:local`.

### 1.5 Redes

`traefik` e `postgres-cluster` (overlay attachable) são as espinhas dorsais. Overlays sem nenhum
container anexado: `arpereira_adv_internal`, `bueno_bueno-net`, `gitlab_default`, `kafka_kafka-net`,
`paperclip_paperclip-internal`, `portainer_agent_network`.

---

## 2. Achados, por risco real

### 🔴 A1 — Supabase Studio aberto na internet, sem autenticação nenhuma

**Evidência**
```
$ curl -sL --resolve supabase-studio.redhusky.com.br:443:167.86.110.111 \
       https://supabase-studio.redhusky.com.br/
final=https://supabase-studio.redhusky.com.br/project/default code=200

$ curl -s .../api/platform/pg-meta/default/tables
200 [{"id":16458,"schema":"auth","name":"users","rls_enabled":true,...,"size":"152 kB",...
```
Sem cookie, sem header, sem basic-auth. O router `supabase-studio@swarm` não tem middleware de
autenticação, e o Studio não roda em modo autenticado (`docker service inspect supabase_studio`
mostra `SUPABASE_SERVICE_KEY=***` e `POSTGRES_PASSWORD=***` injetados no container — o Studio usa
a *service role*, que ignora RLS). Qualquer pessoa que abrir a URL cai direto no editor SQL do
projeto `okane` com privilégio máximo.

**Impacto** — qualquer um na internet lê e escreve em qualquer tabela do `supabase_db`, incluindo
`auth.users` (hashes de senha, e-mails, tokens de sessão), e pode executar SQL arbitrário
(`DROP`, `COPY … TO PROGRAM` onde disponível). É comprometimento total do Supabase e dos dados do
projeto Okane, sem necessidade de credencial.

**Correção** — adicionar middleware `basicAuth` (ou forward-auth) ao router `supabase-studio`, como
já é feito no dashboard do Traefik; ou remover a rota pública e acessar via túnel SSH. **Esforço:
15 min** (2 labels no `docker-stack.yml` do supabase + redeploy da stack).

---

### 🔴 A2 — Tokens de acesso em texto puro em 38 repositórios, e `/root/docker` montado num app web

**Evidência**
```
$ grep 'url = ' /root/docker/postgres/.git/config
  url = https://welintonreis:ghpat_***@githusky.redhusky.com.br/red-huksy/vps/postgres.git
$ ls -la /root/docker/postgres/.git/config
  -rw-r--r-- root root          # 0644, legível por qualquer usuário
```
38 de ~44 repositórios em `/root/docker/*/.git/config` carregam a credencial embutida na URL do
remote. Três emissores distintos:

| Prefixo | Emissor | Onde |
|---|---|---|
| `ghpat_***` | GitHusky (forge próprio) | 35 repos — **é o mesmo token em todos** |
| `glpat-***` | GitLab (desligado, token não revogado) | `plataforma-performance-plus` |
| `ghp_***` | **GitHub.com** (welintonreis) | `jupyter` |

Agravante: os serviços `tera-brain_web` e `tera-brain_worker` montam
`/root/docker → /projects` (read-only). O Tera Brain é uma aplicação web publicada em
`terabrain.redhusky.com.br`. Qualquer path traversal, SSRF-para-arquivo ou RCE nesse app entrega
os 38 tokens de uma vez — mais todos os `.env` do §A4.

**Impacto** — um token vazado dá controle de escrita sobre todo o código da RedHusky no GitHusky
(inclusive `githusky` e `traefik-swarm`, que definem a própria infra). O token `ghp_***` extrapola
a VPS e alcança a conta pessoal no GitHub.com.

**Correção** — trocar os remotes para SSH (`git remote set-url`) ou mover as credenciais para
`~/.git-credentials` com modo 0600 / `credential.helper store`; revogar e reemitir os três tokens;
revogar o `glpat-***` no que sobrou do GitLab. Remover o mount `/root/docker` do tera-brain ou
restringi-lo aos subdiretórios que ele realmente indexa. **Esforço: 1–2 h** (script de rewrite +
rotação de token).

---

### 🔴 A3 — O cluster Postgres inteiro está a uma regra de iptables da internet, e há um caminho IPv6 que ela não cobre

**Evidência — pg_hba permite o mundo**
```
$ tail -4 /root/docker/postgres/pg_hba.conf
# TEMPORÁRIO - REMOVER EM PRODUÇÃO
# Acesso amplo para debug - REMOVER após configurar corretamente
host    all             all             0.0.0.0/0               md5
```
A porta 5432 está publicada no ingress do Swarm (`*:5432` em `ss -tlnp`) e o `pg_hba.conf` aceita
**qualquer origem, qualquer banco, qualquer usuário** com senha. `ssl = off` no `postgresql.conf`,
ou seja, a senha viaja em texto puro. São 54 bancos, 16 GB, incluindo `githusky`, `tera_brain`,
`huskyos_prod`, `husky_brs_production`, `metabase`, `archimedes_production` (11 GB).

**A única proteção** é uma regra de firewall:
```
$ iptables -S DOCKER-USER
-A DOCKER-USER -i eth0 -p tcp -m multiport \
   --dports 5432,6432,5436,9001,8082,8404,11434,6380 -j DROP
```

Três fragilidades nessa proteção:

**(a) IPv6 não é coberto.** A regra é só IPv4. O equivalente v6 está vazio e a policy é permissiva:
```
$ ip6tables -S DOCKER-USER
-N DOCKER-USER                      # chain vazia, nenhuma regra
$ ip6tables -S FORWARD
-P FORWARD ACCEPT
$ ip -6 addr show eth0
    inet6 2a02:c207:2252:4379::1/64 scope global
```
E os listeners são dual-stack — o `docker-proxy` embutido no dockerd atende em `*:5432`,
`*:6432`, `*:8082`, o que inclui IPv6:
```
$ ss -tlnp6 | grep -E ':5432|:8082|:6432'
LISTEN  *:6432   users:(("dockerd",...))
LISTEN  *:8082   users:(("dockerd",...))
LISTEN  *:5432   users:(("dockerd",...))
$ timeout 5 bash -c 'cat </dev/null >/dev/tcp/2a02:c207:2252:4379::1/5432'
v6 5432 ACEITA conexao
$ timeout 5 bash -c 'cat </dev/null >/dev/tcp/2a02:c207:2252:4379::1/8082'
v6 8082 ACEITA conexao
```
O `docker-proxy` atende a conexão em *userspace* (caminho INPUT/OUTPUT), então nem sequer passa
pelo `FORWARD` onde vive o `DOCKER-USER`. *Ressalva honesta:* esse teste saiu do próprio host, o
que não é o caminho externo real; não consegui um ponto de origem fora da VPS para confirmar
(ver §8). Mas não existe nenhuma regra v6 que pudesse bloquear, e não há AAAA publicado que
justifique tratar o v6 como inexistente — o endereço é alcançável independentemente de DNS.

**(b) A regra não sobrevive a reboot por conta própria.** Ela é reaplicada por
`@reboot /usr/local/bin/docker-user-firewall.sh` no crontab do root. O script espera até 60 s pelo
dockerd, mas o cron `@reboot` roda *depois* do Docker já ter subido e publicado as portas — existe
uma janela de segundos a minutos, a cada boot, com 5432 aberta. Não há `netfilter-persistent` nem
unit systemd (`/etc/iptables/` não existe).

**(c) É uma regra única, sem defesa em profundidade.** Um `iptables -F`, um upgrade do Docker que
recrie a chain, ou um erro no script deixam o cluster nu, sem nenhum alerta.

**Impacto** — exposto o 5432, um atacante com uma senha qualquer (ou por força bruta, já que
`log_connections` está ligado mas não há fail2ban) lê e altera todos os 54 bancos: o forge, o
grafo de conhecimento, o financeiro pessoal (`husky_brs_production`), tudo.

**Correção** — em ordem de valor: (1) trocar `host all all 0.0.0.0/0 md5` por faixas de overlay
(`10.0.0.0/8`, `172.16.0.0/12`), que já estão listadas logo acima — a linha do mundo é redundante;
(2) despublicar a porta 5432 do ingress (os apps internos usam `postgres-master:5432` pela overlay,
não precisam dela — ver A5); (3) espelhar a regra em `ip6tables` e persistir ambas via
`netfilter-persistent` em vez de `@reboot`. **Esforço: 30 min** para (1)+(3); (2) exige mexer no
huskyos-prod antes (ver A5).

---

### 🔴 A4 — Segredos versionados em git e enviados ao forge

**Evidência**
```
$ cd /root/docker/postgres && git ls-files | grep -iE 'env|secret|cred|\.sql\.gz'
.env
pg_dumpall_backup.sql.gz
$ cat .gitignore
graphify-out/
.secrets_cache/
PG_MASTER_CREDENTIALS.txt          # protege o arquivo certo, mas .env ficou de fora
$ ls -la .env
-rw-r--r-- root root 66            # POSTGRES_USER / POSTGRES_PASSWORD / POSTGRES_DB
```

| Arquivo | Repo | O que contém |
|---|---|---|
| `.env` | `postgres` | `POSTGRES_PASSWORD` do master, 0644 |
| `pgbouncer/userlist.txt` | `postgres` | senha do usuário `sa` em **texto puro** (`auth_type = plain`) |
| `pg_dumpall_backup.sql.gz` | `postgres` | **1,18 GB** — dump completo do cluster, com roles e hashes, de 2026-04-10 |
| `ssl/key.pem` | `n8n` | **chave privada TLS**, 0644 |
| `.env` | `n8n`, `power-bi-ark`, `plataforma-performance-plus` | credenciais de aplicação |
| `jupyter_cookie_secret` | `jupyter` | segredo de sessão do Jupyter |

Todos com remote configurado e commitados (`git log` confirma `pg_dumpall_backup.sql.gz` no commit
inicial `b373858`) — ou seja, já estão no GitHusky, e o `.git` local pesa 1,2 GB por causa disso.
O `pgbouncer/userlist.txt` é especialmente ruim: `auth_type = plain` significa que não é hash, é a
senha legível do `sa`, que é o usuário que o `huskyos-prod` usa contra o banco de produção.

**Impacto** — quem tiver leitura no GitHusky (ou o token do A2) obtém a senha do Postgres master e
um retrato completo do cluster de abril, sem precisar tocar na VPS.

**Correção** — adicionar ao `.gitignore` e remover do índice (`git rm --cached`); reescrever o
histórico com `git filter-repo` para o dump de 1,18 GB e o `key.pem`; **rotacionar** a senha do
`sa`, do `POSTGRES_PASSWORD` e reemitir o certificado do n8n — o que vazou continua válido até ser
trocado. Migrar o pgbouncer para `auth_type = md5` + `auth_query` (o `auth_query` já está
configurado no `.ini`, só o `auth_type` está errado). **Esforço: 2–3 h**, sendo a rotação de senha
a parte que exige janela.

---

### 🔴 A5 — O backup lógico diário cobre 1 banco de 54

**Evidência**
```
$ grep pg_dump /root/docker/plataforma-redhusky/scripts/pg-dump-daily.sh
if docker exec -i "${MASTER_CTR}" pg_dump -U sa -d redhusky -Fc | \
   aws s3 cp - "s3://${R2_BUCKET}/logical_dumps/redhusky-${TIMESTAMP}.dump" ...
$ tail -2 /var/log/pg-dump-daily.log
Completed 1.1 MiB/1.1 MiB ... [OK] Dump 20260813-0100 enviado ao R2.
```
O cron das 3h roda `pg_dump -d redhusky` — **um único banco, de 23 MB**. O log confirma: 1,1 MiB
por noite. Os outros 53 bancos (16 GB) não entram nesse backup: `githusky` (68 MB, o forge),
`tera_brain`, `huskyos_prod`, `husky_brs_production`, `huskydataops`, `metabase`,
`archimedes_production` (11 GB).

**O que salva parcialmente** — existe WAL-G para o cluster inteiro, e ele *está* funcionando:
```
$ psql -c 'select * from pg_stat_archiver'
archived_count | 63147          failed_count | 0
last_archived_wal | 00000001000001EA00000093   last_archived_time | 2026-08-13 20:45:00
$ wal-g backup-list
base_00000001000001D000000023   2026-08-09T03:56:22Z
```
Então há PITR do cluster completo a partir de **2026-08-09**. Mas:
- existe **um único** base backup (`wal-g delete retain FULL 1` no `walg-entrypoint.sh`); se ele
  estiver corrompido, não há segundo a que recorrer;
- o backup base é um **laço `while true; do … sleep 604800; done` em background dentro do
  container** do Postgres, iniciado pelo entrypoint. Não é supervisionado: se esse subshell morrer,
  nada avisa, o `archive_command` continua empilhando WAL, e a descoberta só acontece na hora do
  restore;
- não há evidência de restore jamais testado (existe `scripts/restore_backup.sh`, nunca executado
  segundo os logs).

**Impacto se o disco falhar agora** — recupera-se o cluster Postgres até 2026-08-09 + WAL
(bom), **desde que** o base backup esteja íntegro. Perde-se, sem nenhum backup: os **13 GB de
`/srv/gitlab`** (única segunda cópia dos repositórios originais, ver A11), os repositórios do
GitHusky (`githusky_repos` 2,2 GB + `githusky_data` 4,9 GB), o MinIO
(`/root/docker/minio/dados-do-minio`), o MSSQL (`/root/docker/mssql/data`), o
`supabase_db_data`, o `supabase_storage_data` e o `redis_redis_data`. Nenhum desses tem rotina de
backup — nem cron, nem job, nem snapshot.

**Correção** — trocar `pg_dump -d redhusky` por `pg_dumpall` ou um laço sobre
`SELECT datname FROM pg_database WHERE NOT datistemplate`; subir `retain FULL` para 2 ou 3;
transformar o laço do WAL-G em cron do host (visível, com log e alerta) em vez de subshell órfão;
e criar backup dos volumes de `githusky_repos`, MinIO e MSSQL. **Esforço: 2 h** para o pg_dumpall
e o retain; **meio dia** para cobrir os volumes.

---

### 🟠 A6 — Cinco rotas TCP do Traefik apontam para entrypoints que não existem; o huskyos-prod fala com o banco em texto puro

**Evidência**
```
$ docker logs traefik_… | grep "EntryPoint doesn't exist"
ERR EntryPoint doesn't exist  entryPointName=postgres-master  routerName=postgres-master@swarm
ERR No valid entryPoint for this router  routerName=postgres-master@swarm
… idem para postgres-read, postgres-analytics, pgbouncer, redis-tcp
$ grep -A1 entryPoints /root/docker/traefik-swarm/traefik.yml
  web: ":80"   websecure: ":443"   metrics: ":8082"   mssql: ":1433"
```
Os serviços declaram routers TCP com TLS em entrypoints `postgres-master`, `postgres-read`,
`postgres-analytics`, `pgbouncer` e `redis-tcp` — **nenhum deles está definido** no `traefik.yml`.
Os cinco routers são descartados no boot e a cada reload de configuração (é essa a origem das
648 mil linhas de log não-access do Traefik, §A8).

A consequência prática está no `huskyos-prod`:
```
$ docker service inspect huskyos-prod_web | grep DATABASE
DATABASE_URL=postgresql://sa:***@pgdb.redhusky.com.br:5432/huskyos_prod
DATABASE_READ_URL=postgresql://sa:***@read.pgdb.redhusky.com.br:5432/huskyos_prod
```
`pgdb.redhusky.com.br` resolve para 167.86.110.111. Como o router SNI está morto, essa conexão
**não passa pelo Traefik e não tem TLS** — ela cai direto na porta 5432 publicada pelo ingress do
Swarm, e só funciona porque o tráfego sai do container pela `docker_gwbridge` (interface que a
regra `-i eth0` do DOCKER-USER não filtra). O `postgresql.conf` tem `ssl = off`, então a senha do
`sa` trafega em claro.

**Impacto** — o app de produção depende de um caminho acidental. No dia em que a regra do
DOCKER-USER for corrigida para bloquear a 5432 em todas as interfaces (A3), ou a porta for
despublicada, o `huskyos-prod` cai — e a causa não vai ser óbvia, porque o nome `pgdb.redhusky.com.br`
sugere que existe um proxy TLS no caminho.

**Correção** — apontar `DATABASE_URL` do huskyos-prod para `postgres-master:5432` pela overlay
`postgres-cluster` (é o que githusky, tera-brain, huskydataops e metabase já fazem) e remover os
5 routers TCP órfãos dos specs. Se o acesso externo por SNI for desejado, aí sim declarar os
entrypoints no `traefik.yml`. **Esforço: 30 min**, e destrava a correção do A3.

---

### 🟠 A7 — pgbouncer e haproxy estão de pé sem ninguém usando

**Evidência**
```
$ psql -c "select datname, usename, client_addr, count(*) from pg_stat_activity
           where backend_type='client backend' group by 1,2,3 order by 4 desc;"
  datname   |  usename   | client_addr | count
 tera_brain | tera_brain | 10.0.7.14   |     5
 postgres   | tera_brain |             |     1
```
Nenhuma conexão vinda do pgbouncer (6432) ou do haproxy. Os `DATABASE_URL` de todos os apps
inspecionados apontam para `postgres-master:5432` direto ou para `pgdb.redhusky.com.br` (A6) —
nenhum para `pgbouncer:6432` ou `haproxy:5432`. O router SNI do pgbouncer está morto (A6). A porta
8404 (stats do haproxy) responde 503 mesmo localmente.

Ainda assim os dois consomem 1 CPU e 1 GB de reserva combinados, publicam três portas no ingress
(6432, 5436, 8404) que a regra do DOCKER-USER precisa cobrir, e o pgbouncer carrega a senha em
texto puro do A4.

**Impacto** — superfície de ataque e reservas de recurso sem contrapartida; três portas a mais para
proteger.

**Correção** — confirmar com um dia de `log_connections` que ninguém conecta, e então remover as
duas stacks (ou zerar réplicas). Some com 3 das 8 portas da lista do DOCKER-USER.
**Esforço: 20 min** após a confirmação.

---

### 🟠 A8 — Nenhuma rotação de log no Docker; 59 GB de build cache; disco em 67%

**Evidência**
```
$ cat /etc/docker/daemon.json
cat: /etc/docker/daemon.json: No such file or directory      # sem log-opts globais
$ docker inspect $(docker ps -q) --format '{{.Name}} {{.HostConfig.LogConfig.Type}} {{.HostConfig.LogConfig.Config}}'
/githusky.1.…            json-file map[]     # map[] = sem max-size, sem max-file
/traefik_traefik.1.…     json-file map[]
… (todos iguais)
$ du -sh /var/lib/docker/containers/*/ | sort -rh | head -4
624M  supabase_analytics
500M  supabase_vector
358M  traefik_traefik
309M  postgres_postgres-master
$ docker system df
Images        85   33 ativas   74.92GB   50.7GB recuperável (67%)
Local Volumes 79   13 ativos   68.07GB   28.1GB recuperável (41%)
Build Cache  408    0 ativos   59.39GB   59.39GB recuperável (100%)
```
Nenhum container tem `max-size`/`max-file`. O log do Traefik cresce especialmente rápido porque
`accessLog` está ligado em JSON **sem filtro** e o probe do A13 gera 404 a cada 10 s — mais as
648 mil linhas de erro de entrypoint do A6.

Fora do Docker: `/var/log/journal` = 4,0 GB, `/var/log/dmesg` = 342 MB, `btmp` (falhas de login) =
45 MB entre os dois arquivos.

**Impacto** — o disco está em 67% (132 GB livres) e cresce por três frentes sem teto. Quando ele
encher, o Postgres master para de escrever WAL e o cluster inteiro trava — mesmo modo de falha do
A3, mas por negligência em vez de ataque.

**Correção** — criar `/etc/docker/daemon.json` com
`{"log-driver":"json-file","log-opts":{"max-size":"50m","max-file":"3"}}` (vale para containers
novos; os atuais só na próxima recriação); `docker builder prune` libera 59 GB imediatamente;
`journalctl --vacuum-size=500M` libera ~3,5 GB. Reduzir o `accessLog` do Traefik a status ≥ 400.
**Esforço: 30 min**, recupera ~110 GB.

---

### 🟠 A9 — Replicação sem replication slot

**Evidência**
```
$ psql -c 'select slot_name, slot_type, active from pg_replication_slots;'
 (0 rows)
$ psql -c 'select current_setting(''wal_keep_size'');'
 1GB
# na réplica:
 pg_is_in_recovery | t     lag | 00:00:01.88
```
A réplica está saudável (2 s de atraso), mas a replicação depende só de `wal_keep_size = 1GB`. Sem
slot, se a `postgres-read` ficar fora do ar tempo suficiente para o master reciclar mais de 1 GB de
WAL, ela não consegue mais alcançar o master e precisa de um `pg_basebackup` completo.

**Impacto** — uma manutenção longa na réplica, ou um pico de escrita durante uma queda dela, custa
um rebuild manual de 16 GB.

**Correção** — criar um slot físico e apontar a réplica para ele (`primary_slot_name`). Atenção ao
contrapeso: slot sem consumidor retém WAL indefinidamente e enche o disco, então convém combinar
com `max_slot_wal_keep_size`. **Esforço: 30 min**, exige reload da réplica.

---

### 🟠 A10 — Rotas e certificados vivos apontando para serviços mortos

**Evidência**
```
$ curl -so /dev/null -w '%{http_code}' --resolve gitlab.redhusky.com.br:443:167.86.110.111 \
       https://gitlab.redhusky.com.br/
404          # idem: kafka, sign, plataforma, pgadmin.pgdb, spark
```
Os hosts resolvem, apresentam certificado LE válido e devolvem 404 — o que confirma a um observador
externo que existe algo ali. Os certificados continuam sendo renovados (todos com validade futura)
e aparecem em Certificate Transparency, publicando o inventário de serviços da casa:

| Host | Serviço | Réplicas | Cert válido até |
|---|---|---|---|
| `gitlab.redhusky.com.br` | `gitlab_gitlab` | 0/0 | 2026-10-13 (61 d) |
| `kafka.redhusky.com.br` | `kafka_kafka-ui` | 0/0 | 2026-09-27 (44 d) |
| `sign.redhusky.com.br` | `documenso_web` | 0/0 | 2026-09-26 (44 d) |
| `plataforma.redhusky.com.br` | `teste-redhusky_nextjs` | 0/0 | 2026-09-15 (33 d) |
| `spark.redhusky.com.br` | `jupyter_pyspark` | 0/0 | — sem cert (conexão falha) |
| `redcloset.redhusky.com.br` | `red-closet_web` | 0/0 | 2026-10-08 (55 d) |
| `archimedes.redhusky.com.br` | `archimedes_web` | 0/0 | 2026-09-18 (35 d) |
| `adegabueno` / `arpereira*` (4) | stacks bueno/arpereira | 0/0 | out/2026 |
| `paperclip.redhusky.com.br` | `paperclip_server` | 0/0 | 2026-09-17 (34 d) |
| `orchestration-dev.redhusky.com.br` | `orchestration-dev_web` | 0/0 | 2026-09-14 (31 d) |
| `consigaz.redhusky.com.br` | `consigaz_app` | **0/1 quebrado** | 2026-11-10 (88 d) |

O `acme.json` guarda **41 certificados**, dos quais 8 são de hosts que nem router têm mais
(`portainer`, `docker`, `app.redhusky.com.br` + wildcard, `rjc`, `evo.rjc`, `dev.huskyos`,
`hml.huskyos`, `financas`) — o serviço `portainer` nem existe mais no swarm, e
`portainer.redhusky.com.br` sequer resolve no DNS.

**Impacto** — inventário público gratuito para quem faz reconhecimento, e risco de que um
`scale=1` acidental reative um serviço desatualizado já roteado e com TLS pronto (ver §6).

**Correção** — remover as labels `traefik.*` dos serviços parados (mantém o serviço declarado,
tira a rota) e podar o `acme.json` das entradas sem router. **Esforço: 1 h.**

---

### 🟠 A11 — 13 GB do GitLab sem backup e sem redundância (⚠ preservar)

**Evidência**
```
$ du -sh /srv/gitlab/*
12G   /srv/gitlab/data        600M  /srv/gitlab/logs      372K  /srv/gitlab/config
$ ls /srv/gitlab/data/git-data/repositories/
+gitaly   @hashed
$ docker service inspect gitlab_gitlab   # mounts
bind:/srv/gitlab/config  bind:/srv/gitlab/logs  bind:/srv/gitlab/data
```
São bind-mounts no disco raiz, sem cópia em outro lugar, sem entrar em nenhum backup (o cron do A5
só toca no Postgres, e o banco do GitLab nem está no cluster principal). São os repositórios
originais, espelhados recentemente para o GitHusky — mas o espelho é a primeira cópia e este volume
é a **segunda e última**.

**Impacto se o disco falhar agora** — perde-se a segunda cópia dos repositórios. O espelho no
GitHusky sobrevive apenas se o `githusky_repos` (também no mesmo disco, também sem backup) sobreviver
— ou seja, na prática **as duas cópias estão no mesmo `/dev/sda1`**. Uma falha de disco leva as duas.

**Correção** — **não apagar nada.** Copiar `/srv/gitlab/data` para o R2 (mesmo bucket do WAL-G,
prefixo separado), uma vez, e depois anualmente; o mesmo para `githusky_repos`. Os 600 MB de
`/srv/gitlab/logs` podem ser descartados sem perda. **Esforço: 1 h** (13 GB de upload).

---

### 🟠 A12 — Quatro serviços reagendando em laço há semanas

Detalhado em §1.2. `postgres_pgadmin` falha com `failed to find a load balancer IP to use for
network` — um problema de IPAM da overlay `postgres-cluster`, não de configuração do pgAdmin; vale
verificar se a overlay está com o pool de IPs esgotado antes de subir qualquer serviço novo nela.
`consigaz_app` referencia uma imagem que não existe no host há 7 semanas, mas mantém rota e
certificado ativos (A10).

**Impacto** — ruído permanente no scheduler, entradas de erro sem fim no log, e um risco silencioso:
se a `postgres-cluster` estiver mesmo sem IPs, o próximo serviço legítimo a subir nela falha igual.

**Correção** — decidir por serviço: corrigir ou zerar réplicas (`replicas: 0` mantém a declaração
sem o laço). Investigar o IPAM da overlay antes. **Esforço: 1 h.**

---

### 🟡 A13 — Higiene e configurações menores

| # | Achado | Evidência | Correção |
|---|---|---|---|
| a | 45 arquivos `.env` com modo **0644** em `/root/docker` (`postgres`, `githusky`, `supabase`, `traefik-swarm`, `redis`, `mssql`…). Apenas 5 estão em 0600. | `find /root/docker -name '.env*' -perm -o=r \| wc -l` → 45 | `chmod 600`; 5 min |
| b | Senha do Redis em texto puro na env `REDIS_URL` do `redhusky-ssh_web` (visível em `docker service inspect` para qualquer um com acesso ao socket) | `docker service inspect redhusky-ssh_web` | mover para Docker secret; 20 min |
| c | Dashboard do Traefik protegido por basicAuth com hash **apr1 (MD5)** | `dynamic/dashboard.yml`: `admin:$apr1$***` | trocar por bcrypt (`htpasswd -B`); 5 min |
| d | Token do provider HTTP em texto puro no `traefik.yml` (`X-Provider-Token`), arquivo 0644 | `/root/docker/traefik-swarm/traefik.yml` | mover para env/secret; 15 min |
| e | Sem redirect global HTTP→HTTPS: só `githusky` responde 301 (e é o app Rails que faz, não o Traefik). `huskyos`, `terabrain`, `metabase` devolvem **404 na porta 80** | `curl --resolve huskyos…:80:…` → 404 | `redirections.entryPoint` no entrypoint `web`; 10 min |
| f | Sem HSTS nem `X-Frame-Options`/`X-Content-Type-Options` em nenhuma resposta (só o `githusky` manda CSP, vinda do Rails) | `curl -I https://githusky…` | middleware `headers` global; 20 min |
| g | Probe externo batendo em `GET /users/sign_in` (rota do **GitLab**) contra `githusky.redhusky.com.br` a cada 10 s, gerando 404 — `RequestCount` já em 227 mil. Monitor não atualizado após a migração do forge | access log do Traefik | corrigir a URL do monitor; 5 min |
| h | 6 overlays sem nenhum container: `arpereira_adv_internal`, `bueno_bueno-net`, `gitlab_default`, `kafka_kafka-net`, `paperclip_paperclip-internal`, `portainer_agent_network` | `docker network inspect … {{len .Containers}}` → 0 | remover junto com as stacks; 10 min |
| i | 5 containers parados e 50,7 GB de imagens não referenciadas | `docker system df` | `docker image prune -a`; 5 min |
| j | Maioria dos serviços ativos sem limite de CPU/memória — `metabase` (1,45 GiB), `supabase_kong` (1,07 GiB) e `mssql` (1,2 GiB) podem crescer sem teto. `redhusky-ssh_worker` já está em **61% do seu limite** de 512 MB e `husky-brs_web` em **38%** de 1 GB | `docker stats --no-stream` | definir limites nos serviços grandes; 1 h |
| k | Dump de 1,18 GB (`pg_dumpall_backup.sql.gz`, abril) parado em `/root/docker/postgres/` além de estar no git (A4) | `ls -la` | mover para o R2 e remover; 15 min |

---

## 3. Superfície de rede — visão consolidada

### Escutando no host

| Porta | Processo | Alcance pretendido | Coberta pelo DOCKER-USER? |
|---|---|---|---|
| 22 | sshd | público | — (INPUT, policy ACCEPT) |
| 80 / 443 | dockerd → Traefik | **público, correto** | não (intencional) |
| 1433 | dockerd → Traefik (entrypoint mssql) | **público, intencional** | não |
| 2223 | docker-proxy → githusky:22 | **público, intencional** (SSH do forge) | não |
| 4416 | dockerd → huskygate | **público, intencional** | não |
| 5432 | dockerd → postgres-master | interno | ✔ IPv4 · ✘ IPv6 (A3) |
| 5436 | dockerd → haproxy | interno (sem uso, A7) | ✔ IPv4 · ✘ IPv6 |
| 6432 | dockerd → pgbouncer | interno (sem uso, A7) | ✔ IPv4 · ✘ IPv6 |
| 6380 | docker-proxy → redis:6379 | interno | ✔ IPv4 · ✘ IPv6 |
| 8082 | dockerd → Traefik (métricas Prometheus) | interno | ✔ IPv4 · ✘ IPv6 |
| 8404 | dockerd → haproxy stats | interno (sem uso) | ✔ IPv4 · ✘ IPv6 |
| 2377 / 7946 | dockerd (control plane do Swarm) | **deveria ser interno** | ✘ **não listada** |
| 11434 | ollama em `172.18.0.1` | bind só na gwbridge, ok | ✔ (e não escuta em eth0) |
| 13001 | docker-proxy em `127.0.0.1` | loopback, ok | — |

Nota sobre 2377/7946: são as portas de gerência do Swarm, escutando em `*` (dual-stack) e ausentes
da lista de DROP. Com um nó único não há tráfego legítimo externo nelas. Merecem entrar na regra.

### Testado de fora (via `--resolve` contra o IP público)

| Host | Código | O que responde sem autenticação |
|---|---|---|
| `supabase-studio.redhusky.com.br` | **200** | 🔴 **Studio inteiro + API** (A1) |
| `s3-console.redhusky.com.br` | 200 | tela de login do MinIO Console (auth exigida) |
| `metabase.redhusky.com.br` | 200 | tela de login do Metabase (auth exigida) |
| `traefik.redhusky.com.br` | **401** | ✔ basicAuth barra corretamente |
| `api-s3.redhusky.com.br` | 403 | ✔ MinIO nega acesso anônimo |
| `supabase.redhusky.com.br` (Kong) | 404 | ✔ sem rota default |
| `gitlab` / `kafka` / `sign` / `plataforma` / `pgadmin.pgdb` | 404 | rotas órfãs (A10) |

---

## 4. Persistência e backup — o que se perde se o disco falhar agora

| Dado | Onde | Tamanho | Backup? |
|---|---|---|---|
| Postgres cluster (54 bancos) | `postgres_postgres_master_data` | 16 GB | ✔ WAL-G (PITR desde 09/08) + dump de 1 banco |
| Repositórios GitLab | bind `/srv/gitlab/data` | 12 GB | ✘ **nenhum** (A11) |
| Repositórios GitHusky | `githusky_repos` + `githusky_data` | 7,1 GB | ✘ **nenhum** |
| MinIO (objetos) | bind `/root/docker/minio/dados-do-minio` | — | ✘ **nenhum** |
| MSSQL | bind `/root/docker/mssql/data` | — | ✘ **nenhum** |
| Supabase | `supabase_db_data` + `supabase_storage_data` | 61 MB+ | ✘ **nenhum** |
| Redis | `redis_redis_data` | — | ✘ **nenhum** |
| Volumes de stacks paradas | `arpereira_pgdata`, `kafka_*`, `paperclip_*`, `bueno_*` | ~3 GB | ✘ (dados históricos) |
| Certificados LE | bind `traefik-swarm/letsencrypt/acme.json` | 517 KB | ✘ (reemissível, mas com rate limit) |

Além disso há **28,1 GB em volumes órfãos** (41% do total) — nomes hash sem serviço associado,
incluindo dois de 15 GB cada, provavelmente restos de containers de banco antigos. Não os removi
nem recomendo remover sem inspecionar o conteúdo primeiro.

**Resumo honesto:** o Postgres está bem coberto; **todo o resto não tem backup nenhum**.

---

## 5. Postgres — quem usa o quê

```
postgres-master (16 GB, 54 bancos, publicado no ingress 5432)
├── githusky, tera-brain(×2), huskydataops, metabase, redhusky-ssh  → postgres-master:5432 (overlay) ✔
├── huskyos-prod (web+worker)                                       → pgdb.redhusky.com.br:5432 ✘ (A6)
├── postgres-read   ← replicação streaming, lag 2 s, sem slot (A9)
├── postgres-analytics (46 MB)  ← nenhum consumidor identificado
├── pgbouncer :6432 ← nenhum consumidor (A7)
└── haproxy   :5436 ← nenhum consumidor (A7)
```

Bancos órfãos / de teste ocupando espaço no master (nenhum tem serviço ativo correspondente):
`archimedes_production` **11 GB** + `_cache` 275 MB + `_cable` 188 MB + `_queue` 21 MB +
`archimedes_development` 9 MB (stack 0/0 desde julho) · `n8n` **1,5 GB** (stack 0/0) ·
`githusky_test_{a,b,c,d,e,f}` + `githusky_test_queue` + `githusky_test_d_queue` +
`githusky_dev_{a,b}` (~110 MB, bancos de worktree paralelos) · `redhusky_0`, `redhusky_1` (27 MB) ·
`okanebkp` (36 MB) · `toca_aqui`, `lwvinhos`, `performance_plus`, `pbiswarm_kb`, `dbt_lab`,
`master_db` (~57 MB). Somados, **~13 GB dos 16 GB do cluster** são de projetos desligados — e todos
entram no base backup semanal do WAL-G, consumindo cota do R2 (que o próprio script comenta ser de
10 GB no plano gratuito).

---

## 6. Serviços com 0 réplicas — veredito individual

Nenhum dos 24 serviços parados mantém reserva de porta no ingress. Confirmado:
```
$ ss -tlnp | grep -E ':2222|:8888|:15692'
(vazio)   # gitlab:2222, jupyter:8888, rabbitmq:15692 → todas livres
```
As portas só são alocadas quando há tarefa rodando. Já as **labels do Traefik permanecem no spec** e
os routers continuam publicados (§A10) — um `scale=1` reativa serviço *e* rota no mesmo instante.

| Serviço | Rota órfã | Cert LE | Volume / dados | Se subir amanhã, é seguro? | Veredito |
|---|---|---|---|---|---|
| `gitlab_gitlab` | `gitlab.…` → 404 | ✔ 61 d | **13 GB** bind `/srv/gitlab` ⚠ **preservar** | Imagem `18.8.6-ce.0` pinada, secret `gitlab_gitlab_root_password` montado, `2222→22` host. Se subir, republica o forge antigo em paralelo ao GitHusky — dois forges com o mesmo conteúdo, divergindo | **Desligado de propósito, manter declarado.** Remover só as labels do Traefik. Volume é a segunda cópia dos repos — **não apagar** (A11) |
| `postgres_pgadmin` | `pgadmin.pgdb.…` → 404 | ✔ 61 d | `postgres_pgadmin-data` | 🔴 **`dpage/pgadmin4:latest`** — sobe uma versão imprevisível de um painel de banco, com secrets `pgadmin_email`/`pgadmin_password`, roteado publicamente. Está em 0/1 **falhando** (IPAM), não desligado | **Precisa decisão.** Pinar a tag e adicionar auth na rota **antes** de qualquer tentativa de subir; ou zerar réplicas de vez |
| `paperclip_db` | — | — | `paperclip_paperclip_pgdata` 72 MB | `postgres:17-alpine` (tag flutuante de minor); um `scale=1` pode puxar um 17.x mais novo que o dado no volume — normalmente ok, mas não é reprodutível | **Lixo provável.** Confirmar com o dono e remover a stack `paperclip` inteira |
| `paperclip_server` | `paperclip.…` → 404 | ✔ 34 d | `paperclip_paperclip_data` | `paperclip:local` — tag que não identifica build nenhum; imagem local, não reproduzível | **Lixo.** Remover junto do `paperclip_db` |
| `jupyter_pyspark` | `spark.…` (sem cert) | ✘ | bind `jupyter/pyspark-data` | 🔴 `jupyter/pyspark-notebook:**latest**`, `8888` no ingress, e o repo tem `jupyter_cookie_secret` versionado (A4). Notebook público = execução de código arbitrário | **Lixo — remover.** Se voltar, exige token e tag pinada |
| `rabbitmq_rabbitmq` | — | — | `rabbitmq_rabbitmq_data` 101 MB | `4.1.0-management-alpine` pinada ✔; publica `15692` (métricas) no ingress, porta **não** coberta pelo DOCKER-USER | **Lixo provável** (nenhum produtor/consumidor no swarm). Se ficar, adicionar 15692 ao DROP |
| `kafka_*` (5 serviços) | `kafka.…` → 404 | ✔ 44 d | `kafka-data`, `zookeeper-data/log` | Tags `7.6.0`/`v0.7.2` pinadas ✔. `kafka-ui` **não tem autenticação** e está roteado publicamente — se subir, expõe tópicos e permite publicar mensagens | **Lixo provável.** Se mantiver, tirar a label do `kafka-ui` primeiro |
| `archimedes_{web,worker,mt5_adapter}` | `archimedes.…` → 404 | ✔ 35 d | `mt5_wine_prefix` 890 MB; **11 GB no Postgres** | Tags `v0.3.87`/`v0.2.1` pinadas ✔, 22 envs com credenciais | **Decisão pendente.** Os 11 GB no master pesam no WAL-G. Se o projeto morreu, exportar e dropar os bancos |
| `arpereira_adv_*` (5) | 4 hosts → 404 | ✔ ~71 d | `pgdata` 246 MB, `n8n_data`, `evolution_data` | 🔴 2 dos 5 em `:latest` (`evolution-api`, `n8n`); banco `n8n` de **1,5 GB** no master | **Cliente encerrado, aparentemente.** Arquivar dados e remover a stack |
| `bueno_{web,worker,bueno-pg}` | `adegabueno.…` → 404 | ✔ 69 d | `bueno_pg_data` 153 MB | Tags pinadas ✔ | **Lixo provável** — confirmar com o dono |
| `documenso_web` | `sign.…` → 404 | ✔ 44 d | — | `v2.14.0` pinada ✔, **7 Docker secrets** bem feitos (`documenso_enc_key`, `_cert_pass`…) | **Desligado de propósito** — é o serviço mais bem configurado da lista. Manter declarado |
| `red-closet_web` | `redcloset.…` → 404 | ✔ 55 d | — | `v0.2.3` pinada ✔, healthcheck ✔ | **Desligado de propósito**, projeto pessoal recente. Manter |
| `orchestration-dev_web` | `orchestration-dev.…` → 404 | ✔ 31 d | `orchestration-dev-storage` | 🔴 Monta **`/var/run/docker.sock` como leitura-escrita** e `/proc`. Um `scale=1` põe um app web de versão `dev-v0.2.14` (não testada) com **root efetivo no host** | **Precisa decisão urgente.** Ambiente `dev` não deveria ter rota pública nem socket rw. Remover a stack dev ou tirar a label + montar o socket como `ro` |
| `plataforma_nextjs`, `plat-redhusky_nextjs`, `teste-redhusky_nextjs` | `plataforma.…` → 404 | ✔ 33 d | binds em `/root/docker/...` e `/srv/redhusky/...` | 🔴 `node:20-bullseye` com bind rw do código-fonte — os três são a **mesma aplicação** apontando para três diretórios diferentes; `plataforma-performance-plus` tem `.env` versionado em git (A4) | **Lixo — três cópias do mesmo experimento.** Manter no máximo uma |

**Padrão que atravessa a tabela:** dos 24 parados, **4 usam `:latest`** e **1 monta o socket do
Docker em rw**. Um `scale=1` acidental em `orchestration-dev_web`, `jupyter_pyspark` ou
`postgres_pgadmin` não devolve o estado de julho — devolve uma imagem imprevisível numa rota que já
está publicada, com certificado já válido. É o risco concreto de manter serviço parado com a
label intacta.

---

## 7. O que está correto

Registrado com o mesmo cuidado dos defeitos:

1. **WAL-G funcionando de verdade.** `archived_count = 63147`, `failed_count = 0`, base backup de
   09/08 no R2 com prefixo isolado por versão + system identifier
   (`pg17/7641750416482078763`) — o comentário no script mostra que a colisão pós-major-upgrade foi
   *pensada*, não descoberta na dor. PITR do cluster inteiro existe.
2. **A regra do DOCKER-USER é a decisão certa.** Depois do incidente de lockout com `ufw`, filtrar
   em `DOCKER-USER` (a única chain que o Docker respeita) em vez de `INPUT` é exatamente o correto —
   `ufw` teria sido contornado pelo DNAT. O script `docker-user-firewall.sh` inclusive documenta o
   porquê e espera o dockerd subir antes de aplicar. As lacunas do A3 são de cobertura (v6,
   persistência), não de conceito.
3. **Replicação saudável** — réplica em `pg_is_in_recovery = t` com 1,88 s de atraso, hot standby
   funcionando.
4. **Docker secrets usados onde importa.** 20 secrets registrados; o `documenso_web` é exemplar
   (7 secrets, zero credencial em env). O `postgres-master` lê usuário, senha e chaves do R2 de
   `/run/secrets/*`, nunca de env.
5. **DNS Cloudflare com proxy desligado**, como a infra exige — todos os hosts testados resolvem
   direto para 167.86.110.111 e o Traefik enxerga o IP real.
6. **TLS bem resolvido no geral:** DNS-01 via Cloudflare (funciona para host sem exposição HTTP) com
   resolver HTTP-01 **separado e com storage próprio** para domínios de cliente — a nota no
   `traefik.yml` explica que é para não colidir com o `acme.json`. Detalhe maduro. Nenhum dos 41
   certificados está vencido ou perto disso (o mais curto tem 30 dias).
7. **`exposedByDefault: false`** no provider do Swarm — serviço só é roteado se pedir explicitamente.
   É o default seguro, e explica por que os 29 serviços sem label não têm exposição HTTP nenhuma.
8. **Dashboard do Traefik com `api.insecure: false` + basicAuth**, retornando 401 na verificação
   externa. Só o algoritmo do hash é fraco (A13c).
9. **A opção TLS `nohttp2` está documentada no próprio arquivo** com o motivo (WebSocket sobre HTTPS
   precisa de `http/1.1` no ALPN) — quem mexer daqui a seis meses não vai desfazer sem entender.
10. **Healthchecks nos serviços que mais importam:** postgres master/read/analytics, haproxy, redis,
    mssql, huskyos-prod_web, husky-brs, redhusky-ssh (web e worker), supabase db/meta/studio.
11. **Limites de recurso onde há histórico de estouro** — `husky-brs_web`, `redhusky-ssh_*`,
    `bueno_*`, `okane`, `consigaz` têm CPU e memória fixados com reserva.
12. **`.gitignore` do repo `postgres` protege `PG_MASTER_CREDENTIALS.txt` e `.secrets_cache/`**, e
    ambos estão em **0600**. A intenção estava certa — o `.env` é que escapou (A4).
13. **Backup lógico com streaming direto para o R2**, sem escrever em disco intermediário, com
    ponteiro `_latest.dump` e hook de alerta opcional. A engenharia do script é boa; o problema é o
    escopo de um banco só (A5).
14. **Nenhum container privilegiado, nenhum `cap_add`** em todo o swarm.
15. **`graphify-out/` e `.secrets_cache/` no `.gitignore`** — artefato de ferramenta não polui repo.

---

## 8. Não coberto

1. **Confirmação externa do bloqueio de portas (A3).** Todos os testes de porta saíram do próprio
   host. Conexão local para o IP público percorre `OUTPUT`, não `FORWARD`, então **não passa pelo
   `DOCKER-USER`** — por isso 5432/8082/6380 "aceitaram conexão" nos testes e isso *não* prova
   exposição externa. Tentei um scanner externo via `WebFetch` (`api.hackertarget.com`, exigiu
   chave) e um GET direto em `http://167.86.110.111:8082` (o `WebFetch` força upgrade para HTTPS e
   falhou no certificado). **Confirmar de fora**, de outra máquina:
   `nmap -Pn -p 5432,6432,5436,8082,8404,6380,2377,7946 167.86.110.111` e o mesmo com `-6` contra
   `2a02:c207:2252:4379::1`. O caminho IPv6 do A3 é a hipótese mais importante a validar.
2. **Se o Supabase Studio já foi acessado por terceiros.** Não li o access log do Traefik em busca
   de requisições a `supabase-studio` vindas de IPs desconhecidos — o log tem centenas de milhares
   de linhas e a análise de comprometimento é um trabalho à parte. **Recomendo fortemente fazer
   isso**, dado o A1: `docker logs <traefik> | grep supabase-studio | jq -r .ClientHost | sort -u`.
3. **Integridade do base backup do WAL-G.** Confirmei que o backup existe e que o WAL flui, mas não
   executei `wal-g backup-fetch` para um diretório temporário — seria a única prova real de que o
   restore funciona, e exigiria espaço em disco e tempo. **É a verificação de maior valor pendente.**
4. **Conteúdo dos 28 GB de volumes órfãos**, incluindo dois de 15 GB com nome hash. Identificá-los
   exige montá-los ou inspecionar arquivos, e eu não quis tocar em dado possivelmente vivo.
5. **CVEs das imagens.** Não rodei scanner (Trivy/Grype não estão instalados, e a regra da casa
   proíbe instalar no host). As idades das tags dão o indicativo — `kong:2.8.1` (2022),
   `supabase/postgres:15.8.1`, `timberio/vector:0.28.1-alpine` (2023) são as mais atrasadas entre as
   que **estão rodando**. Sugiro rodar o Trivy em container contra os digests.
6. **Se `postgres-analytics` e `redis` têm consumidores.** Baseei-me em `pg_stat_activity` num
   instante único e nas envs dos serviços; um consumidor intermitente (job noturno) não apareceria.
   Antes de remover qualquer coisa do A7, ligar `log_connections` por 24 h.
7. **Regras da Cloudflare** (WAF, rate limiting, Access). Só verifiquei que o proxy está desligado
   via DNS; não tenho as credenciais do painel, e o `CF_DNS_API_TOKEN` do Traefik não deve ser usado
   para isso.
8. **Hardening do SSH do host (porta 22)** e estado do fail2ban. Os 45 MB de `btmp` indicam volume
   alto de tentativas de login falhas, mas não auditei `sshd_config` nem políticas de bloqueio —
   estava fora do escopo de Docker/Swarm, e merece uma passada própria.
9. **Conteúdo dos 24 arquivos de auditoria anteriores** (`/root/security-audit-redhusky-2026-07-06.md`
   e `.html`) — não os li, então não sei quais destes achados já eram conhecidos, nem se algum foi
   aceito conscientemente como risco.
