# Spec — Migração SQLite → Postgres

**Status:** implementado — v0.9.55
**Data:** 2026-09-01

## Problema

`orchestration-prod_web` estava crash-looping: migration
`20260901100000_convert_vps_and_sessions_to_uuid.rb` usava
`default: -> { "gen_random_uuid()" }`, função que não existe em SQLite —
o app nunca rodou Postgres apesar da premissa inicial, `database.yml`
apontava `adapter: sqlite3` em tudo.

Investigar isso expôs um bug real na infra Postgres compartilhada
(`~/docker/postgres/`): PgBouncer estava na frente do HAProxy, invertido do
padrão enterprise. Corrigido junto (ver `~/docker/postgres/README.md`) —
nenhum outro app do swarm usava esse caminho ainda, seguro de arrumar.

## Decisão

Adotar a migração do orchestration como o gatilho pra:
1. Corrigir a topologia da infra Postgres compartilhada: **App → HAProxy → PgBouncer → Postgres (primary/réplicas)**. Patroni deliberadamente fora de escopo agora.
2. Migrar orchestration pra essa infra, preservando os dados reais existentes (não zerar).
3. Tornar esse o padrão default pra projetos Rails novos (`novo-projeto-rails` skill).

## O que mudou no app

- **Gemfile**: `sqlite3` → `pg`.
- **`config/database.yml`**: `primary`/`cache`/`queue`/`cable` todos lendo `DATABASE_URL` (mesma URL — tabelas namespaced, sem colisão, padrão do gerador Rails 8 quando não há bancos dedicados). Fallback local só pra não quebrar o boot durante `assets:precompile` no build da imagem (esse estágio não tem `DATABASE_URL`, nunca conecta de verdade).
- **Dockerfile**: troca `libsqlite3-dev`/`libsqlite3-0` por `libpq-dev`/`libpq5`. `sqlite3` CLI mantido só no build stage.
- **Migrations**: a migration quebrada foi deletada. Em vez de `change_column` pós-hoc, `id: :uuid` foi embutido direto nos `create_table` originais de `sessions`, `vps_hosts`, `vps_terminal_sessions` (+ `type: :uuid` no FK `vps_host_id`). Sem `pgcrypto`/default no banco — os models já mintam UUID em Ruby (`before_create :set_uuid_id`). `users`/demais FKs continuam integer.
- **`deploy/orchestration.stack.yml` / `deploy/deploy-prod.sh`**: `DATABASE_URL` construída a partir de `.db_password` (gitignored) e exportada antes do `docker stack deploy`, apontando pra `haproxy:6432` — não pra `postgres-master` direto. Rede `postgres-cluster` anexada ao serviço `web`.

## Role + database

`orchestration_app` / `orchestration`, criados via serviço throwaway
(`--restart-condition none`) contra `postgres-master`. Senha em
`~/docker/redhusk-orchestration/.db_password` (chmod 640, gitignored).
Entrada em `pgbouncer/userlist.txt` — **texto plano**, não hash: `auth_type
= plain` no `pgbouncer.ini` exige isso, `auth_query` não é usado nesse modo.

## Migração de dados

29 tabelas no schema; 14 tinham dados reais em produção (users,
environments, shared_credentials, app_settings, app_templates,
git_credentials, ai_accounts, ai_quota_snapshots, audit_logs, alerts,
host_metrics, vps_hosts, vps_terminal_sessions, sessions —
~8.5k linhas totais, dominado por `alerts`/`host_metrics`).

Execução real (a sessão caiu no meio, retomada de fora do container):

1. `production.sqlite3` lido direto do volume Docker
   (`orchestration-prod_orchestration-storage`), montado read-only num
   container `alpine` throwaway com `sqlite3` instalado via `apk`.
2. Cada tabela exportada pra CSV (`sqlite3 -header -csv`) com as colunas na
   ordem do `schema.rb`.
3. Tabelas integer-PK: `psql \copy` direto do CSV pro Postgres, preservando
   o `id` original, seguido de `setval(pg_get_serial_sequence(...), max(id))`
   por tabela pra sequence não colidir.
4. Tabelas UUID-PK (dataset pequeno — 1 `vps_hosts`, 6
   `vps_terminal_sessions`, 16 `sessions`): `INSERT` manual em SQL, deixando
   o Postgres mintar o UUID novo (`RETURNING id \gset`) e reusando esse
   valor nos `INSERT`s de `vps_terminal_sessions` que referenciam
   `vps_host_id`. `sessions` não tem UUID a remapear (FK é só `user_id`,
   integer) — copiado direto via `\copy` sem a coluna `id`.
5. Tudo dentro de `psql --single-transaction -v ON_ERROR_STOP=1`: qualquer
   erro reverte a carga inteira, sem estado parcial.

**Armadilha**: a primeira tentativa de recriar o schema usou
`db:schema:load` contra o `schema.rb` do disco, que ainda tinha o
snapshot pré-UUID. Resultado: `sessions`/`vps_hosts`/
`vps_terminal_sessions` foram criadas com PK `bigint` mesmo com as
migrations já corrigidas (task #4). Corrigido rodando `db:drop db:create
db:migrate` (migrations reais, não o schema.rb velho) — precisou também
`DISABLE_DATABASE_ENVIRONMENT_CHECK=1` (Rails bloqueia `db:drop` contra
`RAILS_ENV=production` mesmo num banco novo sem tráfego) e matar a sessão
Postgres que ainda segurava o banco aberto (`pg_terminate_backend`, como
`sa`/superuser — a role de aplicação não tem `pg_signal_backend`).

**Verificação**: contagem de linhas SQLite vs Postgres bateu nas 14
tabelas. Joins de FK (`vps_terminal_sessions↔vps_hosts`,
`sessions↔users`, `audit_logs↔users`, `ai_quota_snapshots↔ai_accounts`)
bateram em contagem total.

## Não migrado (proposital)

`production_cache.sqlite3`, `production_queue.sqlite3`,
`production_cable.sqlite3` — dados transientes/regeneráveis do Solid
Cache/Queue/Cable, sem necessidade de preservar.

## Ceiling / upgrade path

`ponytail:` script de migração de dados foi one-off, não idempotente, sem
retry — rodou uma vez contra dataset pequeno (~8.5k linhas totais,
dominado por `alerts`/`host_metrics`). Se precisar re-rodar por causa de
mudança de schema, escrever de novo, não reusar o script deletado.
