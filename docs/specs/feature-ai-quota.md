# Feature — Quotas de IA nativas

> Status: 📋 planejada · Escrita 2026-09-01

## Problema

Existia uma tela "Quotas de IA" no Orchestration que era só um `<iframe>`
cross-origin apontando para o dashboard do 9router. Isso não é uma tela do
Orchestration: depende do 9router estar de pé, exige login separado nele, e
não participa de nada da plataforma (nem tema, nem breadcrumb, nem auditoria).

## Decisão de arquitetura

**O Orchestration não fala com o 9router.** O 9router é referência visual e de
comportamento, do mesmo jeito que o Portainer foi referência para o
Orchestration inteiro — não é uma dependência de runtime.

Consequência: o Orchestration passa a ter **contas de IA próprias**, com
credenciais no banco dele, refresh de token próprio, e consulta direta às APIs
de quota de cada provedor. Isso é reimplementar a gestão de contas, não só
desenhar uma tela — daí o faseamento.

**Custo aceito conscientemente:** duas cópias de credencial do mesmo provedor
(uma no 9router, uma aqui), cada uma renovando seu token. Provedores que
invalidam o refresh token anterior a cada renovação vão brigar entre si; se
acontecer, a saída é o Orchestration virar dono da credencial e o 9router
consumir dele, nunca o contrário.

## Modelo de dado normalizado

Todo fetcher devolve a mesma forma, independente do provedor:

```ruby
{ plan:, message:, quotas: [ { name:, model_key:, used:, total:,
                               remaining_pct:, reset_at:, recurring:, unlimited: } ], extra: {} }
```

`remaining_pct` segue esta cadeia, nesta ordem: o valor que o provedor mandou →
`remaining_percentage` → derivado de `used`/`total`, onde `total` zero ⇒ 0,
`used` ausente ou negativo ⇒ 100, `used >= total` ⇒ 0.

**Armadilha de nomenclatura:** `remaining_pct` é percentual, enquanto `used` e
`total` são contagens brutas — exceto em claude e codex, onde `total` é
literalmente `100` porque o provedor já reporta em percentual.

Cores: `> 70` verde, `>= 30` amarelo, resto vermelho. Conta "vazia" =
`total > 0 && remaining_pct <= 5`.

## Fórmula por provedor

| Provedor | Endpoint | Agregação |
|---|---|---|
| claude | `GET api.anthropic.com/api/oauth/usage` | `used = utilization` (0–100), `total = 100`, `reset_at = resets_at`. Buckets: `five_hour` → `session (5h)`, `seven_day` → `weekly (7d)`, `seven_day_<x>` → `weekly <x> (7d)` |
| codex | `GET chatgpt.com/backend-api/wham/usage` | `used = clamp(used_percent, 0, 100)`, `total = 100`. `primary_window` → `5h`, `secondary_window` → `Weekly`, mais os prefixos `review_` e `spark_`. Extras: `plan`, `limitReached`, `resetCredits.availableCount` |
| antigravity | `POST cloudcode-pa.googleapis.com/v1internal:fetchAvailableModels` | por modelo: `total = 1000`, `used = 1000 - round(1000 × remainingFraction)`, `remaining_pct = 100 × f`. Pula `isInternal` |
| gemini-cli | `POST cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota` | idem antigravity |
| github | `GET api.github.com/copilot_internal/user` | `used = entitlement - remaining`, `total = entitlement`, respeita `unlimited`. Quotas `chat`, `completions`, `premium_interactions`, com `reset_at = quota_reset_date` compartilhado |

**Claude limita agressivamente:** cache de 5 min por token e cooldown de 3 min
depois de um 429. Os demais, 60s. `?force=1` fura o cache — nunca em rotina.

## Fases

### A1 — Contas e credenciais
`AiAccount` (`provider`, `auth_type`, `name`, `email`, `display_name`,
`priority`, `active`, `test_status`, `last_error`, `last_error_at`,
`last_used_at`, `credentials` cifrado, `provider_data` JSON).

Cifra com **ActiveRecord::Encryption** — built-in do Rails 8, sem gem nova.

Ingestão sem depender de fluxo OAuth interativo: importar de arquivo local
(`~/.claude/.credentials.json` e `~/.codex/auth.json` já existem no host,
montados read-only) ou colar JSON na UI. Refresh por provedor em
`app/services/ai_quota/refresh/<provider>.rb`, disparado antes de qualquer
chamada de quota quando `expires_at` estiver perto de vencer.

### A2 — Fetchers
Um PORO por provedor em `app/services/ai_quota/fetch/`, mais um dispatcher
`AiQuota::Usage.for(account)` que devolve `{ message: "não implementado" }`
para provedor sem fetcher.

### A3 — Snapshots
`AiQuotaSnapshot` + job recorrente de 15 min. O 9router **não guarda histórico
nenhum** — quota lá é sempre consulta ao vivo. Este é o dado que a plataforma
passa a ter e ele não tem. Retenção de 90 dias, purga no mesmo job. Sparkline
em SVG inline, sem gem de gráfico.

### A4 — Tela
Resumo no topo em stat tiles (contas ativas, contas vazias, menor quota do
parque, próxima janela a resetar) — isso o 9router não tem. Grid de cards por
conta com as linhas de quota, filtros, ordenação, auto-refresh de 60s, e as
ações (ligar/desligar, desligar vazias, esconder linha, reset credits do
codex), todas auditadas via `AuditLog`.

Cada card busca sua quota num turbo-frame lazy: o browser paraleliza as N
chamadas upstream e o Rails não precisa de thread nenhuma. O skeleton vem do
`Ui::SkeletonComponent` variante `:cards` — ver
[feature-loading-skeletons](feature-loading-skeletons.md).

### A5 — Deploy
Bind-mount read-only de `~/.claude` e `~/.codex`; chaves de cifra via
`RAILS_MASTER_KEY`, que já existe. Sem porta nova, sem rede nova.

## Verificação

Comparar lado a lado com a tela do 9router **no mesmo minuto** — os números têm
que bater. É o único critério honesto de "mesmos dados". Depois: forçar
`expires_at` no passado e confirmar que a conta se recupera sozinha.

## Fora de escopo

Provedores sem fetcher nesta fase (`kiro`, `qoder`, `zed`, `grok-cli`,
`ollama`, variantes `-cn`); login OAuth interativo dentro do Orchestration
(importa credencial e renova — login novo continua no CLI de cada provedor);
roteamento e inferência (o Orchestration mostra quota, não vira gateway).
