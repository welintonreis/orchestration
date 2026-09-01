# Spec — Plano de Migração de Apps para Topologia HAProxy → PgBouncer → Postgres

**Status:** Rascunho / Planejamento
**Data:** 2026-09-01
**Topologia Alvo:** App → HAProxy (6432 escrita / 5432 leitura) → PgBouncer (6432) → Postgres (master/réplica)

## Contexto

A topologia enterprise de pool e balanceamento de conexões PostgreSQL no host `redhusky-lab-01` foi invertida e padronizada para:
`App → HAProxy (porta 6432 escrita) → PgBouncer (porta 6432) → postgres-master (5432)`

O primeiro app migrado e validado nessa topologia foi o `orchestration` (v0.9.55).

Este documento inventaria os demais apps ativos no Swarm para planejamento futuro de migração, sem execução imediata.

---

## 1. Inventário de Apps Ativos no Swarm

### 1.1 `githusky`
- **Serviço Swarm:** `githusky` (1/1)
- **Repo:** `~/docker/githusky`
- **Tecnologia:** Rails 8.1
- **Conexão Atual:** Conecta direto em `postgres-master:5432`
- **Requisitos para Migração:**
  1. Criar role/db dedicados se ainda compartilhar com outro usuário (`githusky_app` / `githusky`).
  2. Adicionar entradas em `~/docker/postgres/pgbouncer/pgbouncer.ini` (`githusky = host=postgres-master port=5432 dbname=githusky`).
  3. Adicionar credencial em `~/docker/postgres/pgbouncer/userlist.txt`.
  4. Atualizar `DATABASE_URL` no stack deploy para `postgresql://githusky_app:...@haproxy:6432/githusky`.
  5. Anexar rede `postgres-cluster` (já deve ter).
- **Risco / Impacto:** Baixo/Médio (forge git principal, requer janela curta para restart).

### 1.2 `huskydataops`
- **Serviço Swarm:** `huskydataops_web` (1/1)
- **Repo:** `~/docker/huskydataops`
- **Tecnologia:** Rails 8.1
- **Conexão Atual:** Conecta direto em `postgres-master:5432`
- **Requisitos para Migração:**
  1. Cadastrar alias no PgBouncer + userlist.
  2. Apontar `DATABASE_URL` para `haproxy:6432/huskydataops`.
- **Risco / Impacto:** Baixo.

### 1.3 `husky-brs`
- **Serviço Swarm:** `husky-brs_web` (1/1)
- **Repo:** `~/docker/husky-brs`
- **Tecnologia:** Rails 8.1
- **Conexão Atual:** Conecta direto em `postgres-master:5432`
- **Requisitos para Migração:**
  1. Cadastrar alias no PgBouncer + userlist.
  2. Apontar `DATABASE_URL` para `haproxy:6432/husky_brs`.
- **Risco / Impacto:** Baixo.

### 1.4 `huskyos-prod`
- **Serviços Swarm:** `huskyos-prod_web` (1/1), `huskyos-prod_worker` (1/1)
- **Repo:** `~/docker/huskyos`
- **Tecnologia:** Rails 8
- **Conexão Atual:** Conecta direto em `postgres-master:5432`
- **Requisitos para Migração:**
  1. Cadastrar alias no PgBouncer + userlist.
  2. Atualizar tanto `web` quanto `worker` para `DATABASE_URL` via `haproxy:6432`.
- **Risco / Impacto:** Médio (app com worker ativo processando background jobs).

### 1.5 `red-closet`
- **Serviço Swarm:** `red-closet_web` (0/0 no momento)
- **Repo:** `~/docker/red-closet`
- **Tecnologia:** Rails 8
- **Requisitos para Migração:**
  1. Ajustar deploy stack antes de subir réplicas.

---

## 2. Padrão de Onboarding para Novos Projetos

Conforme documentado em `~/docker/postgres/README.md` e no skill `novo-projeto-rails`:
1. Database e Role criados via script/query SQL no `postgres-master`.
2. Senha mantida em `.db_password` no diretório do projeto.
3. Alias no `pgbouncer.ini` + plaintext password no `userlist.txt`.
4. `DATABASE_URL` gerada no script de deploy apontando sempre para `haproxy:6432/<db_name>`.
