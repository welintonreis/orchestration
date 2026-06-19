# Spec — GitOps Reconcile (Argo CD-inspired)

**Status:** implementado — v0.7.0
**Versão alvo:** v0.7.0

> Implementado: `GitDriftService` (drift read-only + diff normalizado), colunas
> `sync_status`/`health`/`self_heal`/`sync_window`/`pre_sync_cmd`/`post_sync_cmd`,
> tabela `git_stack_revisions` + rollback, ações `sync`/`rollback`/`refresh_drift`,
> self-heal + sync window no `GitAutoPollJob`, hooks Pre/PostSync + gravação de
> revisões no `GitDeployer`, UI de drift/badges/histórico em `/git_stacks`.
> Nota: protocolo ttyd real usa prefixo de comando em ambas direções (output
> também `0`), corrigido na implementação vs descrição simplificada do spec.

---

## Problema com Git Deploy atual

Modelo hoje = **push/poll → deploy cego**. `GitPollService` faz `git ls-remote`,
compara SHA; se mudou, `GitDeployer` roda `docker stack deploy`. Nunca olhamos o
**estado vivo** do Swarm.

| Problema | Causa raiz |
|---|---|
| Drift invisível | Alguém faz `docker service update` na mão → divergência do Git nunca detectada |
| Deploy é cego | Sem diff desejado-vs-live antes de aplicar |
| `status` único confuso | `idle/deployed/failed` mistura "bate com Git?" e "está saudável?" |
| Sem rollback | Guardamos só `last_commit_sha`; voltar versão = manual |
| Sem trilha | Histórico de deploys não persistido |

---

## Conceitos Argo CD mapeados p/ Swarm

| Argo (K8s) | Equivalente Swarm | Aproveita |
|---|---|---|
| Application = repo+path+cluster | `git_stack` = repo+compose+environment | já existe |
| Sync Status (Synced/OutOfSync) | compose renderizado vs `docker service inspect` | **novo** |
| Health Status (Healthy/Degraded/Progressing) | task states (`docker service ps`) | **novo** |
| `last-applied-configuration` | compose normalizado salvo por revision | **novo** |
| Self-heal | re-aplica Git ao detectar drift | estende `auto_update` |
| Manual vs Auto sync | já temos `auto_update` boolean | estende |
| Rollback / history | tabela `git_stack_revisions` | **novo** |
| Sync windows | janela allow/deny no `GitAutoPollJob` | **novo** |
| PreSync/PostSync/SyncFail hooks | comandos pre/post por stack | **novo** |
| App-of-Apps / ApplicationSet | já temos `environments`/teams/roles | pular |
| Helm/Kustomize/Lua health | sem equivalente forte; já temos `.env` subst | pular |

---

## Solução proposta

### 1. Split de status — Sync vs Health

Hoje `git_stacks.status` (`idle/deployed/failed`) mistura dois eixos. Separar:

- `sync_status`: `synced` / `out_of_sync` / `unknown`
- `health`: `healthy` / `progressing` / `degraded` / `missing`

`status` legado vira derivado (ou removido depois).

### 2. GitDriftService — coração da feature

`app/services/git_drift_service.rb`, **read-only** (não aplica nada):

1. Renderiza compose desejado (repo no SHA alvo + `.env` substituído) → normaliza.
2. Lê estado vivo: `docker stack services <stack>` + `docker service inspect`.
3. Diff campo-a-campo (image, replicas, env, labels declaradas, mounts, ports).
4. Popula `sync_status` + grava o diff p/ a UI.

Health em paralelo via `docker service ps`: task `Running` vs `Shutdown/Rejected/Failed`.

### 3. Diff view na UI `/git`

Badge **Synced** (verde) / **OutOfSync** (âmbar) por stack. Expandir → diff
desejado-vs-live (estilo Argo). Botão **Sync** aplica; deploy deixa de ser cego.

### 4. Self-heal (opt-in por stack)

Coluna `self_heal` boolean. Quando `true` + drift detectado → `GitDeployer`
re-aplica Git automaticamente (não só em commit novo). Default `false` (seguro).

### 5. Revisions + rollback

Tabela `git_stack_revisions`:

| coluna | tipo | nota |
|---|---|---|
| git_stack_id | int | FK |
| sha | string | commit aplicado |
| normalized_compose | text | `last-applied` p/ three-way diff |
| image_digests | text (json) | digests resolvidos no deploy |
| deploy_output | text | stdout/stderr |
| deployed_at | datetime | |

Rollback 1-clique = checkout `sha` anterior + redeploy. Diff three-way usa
`normalized_compose` da última revision (evita falso drift, ver gotcha).

### 6. Sync windows

`AppSetting` ou coluna por stack: janelas allow/deny (cron-like). `GitAutoPollJob`
pula deploy fora da janela, marca `sync_status=out_of_sync` + alerta "pending".

### 7. Sync hooks Pre/Post

Por stack: `pre_sync_cmd` / `post_sync_cmd` / on-fail. Roda em job isolado.
Wire eventos (sync ok, drift, fail, health degraded) nos `Alert`/`Notification`
que já existem.

---

## Gotcha crítico — normalização do diff

Swarm **injeta defaults** no `service inspect` → diff ingênuo = **sempre OutOfSync**
(falso positivo). Fontes de ruído:

| Ruído | Origem |
|---|---|
| Digest de imagem resolvido | `nginx:1.25` no compose vs `nginx:1.25@sha256:...` no live |
| Labels `com.docker.stack.*` | injetadas pelo `stack deploy`, não estão no compose |
| Ordem de `Env` | array reordenado pelo Docker |
| Defaults de `update_config` / `restart_policy` | preenchidos quando omitidos |
| `Mode.Replicated.Replicas` default 1 | omitido no compose, presente no live |

**Solução = three-way diff normalizado** (igual Argo com `last-applied-configuration`):

- Comparar **desejado** vs **last-applied** (`normalized_compose` da revision), não vs
  o live cru.
- Normalizador descarta labels geradas, ignora digest se a tag bate, ordena `Env`,
  injeta os mesmos defaults dos dois lados antes de comparar.

Esse normalizador é o trabalho real do item (2). Sem ele a feature não serve.

---

## Migrations

```ruby
add_column :git_stacks, :sync_status, :string, default: "unknown"
add_column :git_stacks, :health,      :string, default: "unknown"
add_column :git_stacks, :self_heal,   :boolean, default: false
add_column :git_stacks, :last_drift_at, :datetime
add_column :git_stacks, :drift_detail,  :text   # JSON do último diff

create_table :git_stack_revisions do |t|
  t.references :git_stack, null: false, foreign_key: true
  t.string  :sha
  t.text    :normalized_compose
  t.text    :image_digests
  t.text    :deploy_output
  t.datetime :deployed_at
  t.timestamps
end
```

---

## Riscos e mitigações

| Risco | Impacto | Mitigação |
|---|---|---|
| Normalização incompleta → falso OutOfSync | Usuário ignora badge (alarme falso) | Three-way diff + lista de campos ignorados auditada |
| Self-heal reverte mudança emergencial legítima | Operador perde hotfix manual | Default `false`; aviso na UI; log de cada self-heal |
| `service inspect` de stack grande = lento | Poll trava | Cache por SHA; só re-inspeciona em mudança ou intervalo |
| Rollback p/ SHA sem imagem no host | Deploy falha (`--resolve-image never`) | Validar digest disponível antes; senão rebuild |
| Sync window mal configurada bloqueia deploy urgente | Deploy preso | Botão "Sync agora" ignora janela (override admin) |

---

## O que NÃO muda

- `GitPollService` (`git ls-remote`) — mantido, vira gatilho do drift check
- `GitDeployer` — reusado pelo Sync/self-heal/rollback
- Wizard `/git_stacks` (source git/yaml/zip) — igual
- `.env` substitution existente — reusada na renderização do compose desejado

---

## Ordem de implementação sugerida

1. **Fase 1 (read-only, baixo risco):** `GitDriftService` + normalizador + colunas
   `sync_status`/`health`/`drift_detail`. Badge OutOfSync na UI `/git`. **Não** aplica
   nada. Destrava tudo abaixo.
2. **Fase 2:** Diff view expandível + botão Sync manual (reusa `GitDeployer`).
3. **Fase 3:** `git_stack_revisions` + rollback 1-clique.
4. **Fase 4:** Self-heal opt-in + sync windows.
5. **Fase 5:** Sync hooks Pre/Post + eventos nos Alert/Notification.
