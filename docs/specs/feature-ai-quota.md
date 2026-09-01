# Feature — Quotas de IA nativas

> Status: ✅ A1–A6 entregues · Escrita e implementada 2026-09-01

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

**O risco previsto aconteceu, no mesmo dia.** Ao renovar o token do Codex em
2026-09-01, o endpoint devolveu um **refresh token novo** — a rotação é padrão
lá. Duas cópias independentes da mesma credencial se invalidam mutuamente: quem
renova por último deixa a outra com um token morto.

Por isso o desenho final **não** tem duas cópias. A conta guarda um
`credential_source`:

- `file` — aponta para o arquivo de credencial de um CLI já autenticado neste
  host (`~/.claude/.credentials.json`, `~/.codex/auth.json`). Quando o
  Orchestration renova, ele **grava de volta nesse arquivo**, atomicamente
  (escreve temporário, `rename` por cima, modo 600). Um dono, uma credencial.
- `inline` — credencial colada aqui, cifrada na coluna, que é nossa para
  renovar.

A fase A1 não teve fluxo de login OAuth interativo, e isso foi deliberado
**para contas `file`**: logar de novo mintaria uma segunda credencial para a
mesma conta que o CLI já possui, recriando exatamente a briga de rotação que o
desenho evita. Esse risco não existe para uma conta nova — daí a fase A6.

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
| codex | `GET chatgpt.com/backend-api/wham/usage` | `used = clamp(used_percent, 0, 100)`, `total = 100`. As janelas ficam **dentro de `rate_limit`** (`primary_window`/`secondary_window`), com as famílias `code_review_rate_limit` e `spark_rate_limit` ao lado. `reset_at` é **epoch em segundos**. Extras: `plan_type`, `email`, `rate_limit.limit_reached`, `rate_limit_reset_credits.available_count`, `credits` |
| antigravity | `POST cloudcode-pa.googleapis.com/v1internal:fetchAvailableModels` | por modelo: `total = 1000`, `used = 1000 - round(1000 × remainingFraction)`, `remaining_pct = 100 × f`. Pula `isInternal` |
| gemini-cli | `POST cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota` | idem antigravity |
| github | `GET api.github.com/copilot_internal/user` | `used = entitlement - remaining`, `total = entitlement`, respeita `unlimited`. Quotas `chat`, `completions`, `premium_interactions`, com `reset_at = quota_reset_date` compartilhado |

**Claude limita agressivamente:** cache de 5 min por conta. Codex, 60s.
`force: true` fura o cache — nunca em rotina.

**O nome da janela do Codex é dado, não posição.** Cada janela traz
`limit_window_seconds`; a conta de teste é `free`, com janela de **30 dias**.
Rotular a primeira janela como "5h" por convenção mostraria "Sessão (5h)" numa
quota mensal. O rótulo sai do tamanho da janela, com fallback humanizado.

**O formato real divergiu do que o bundle do 9router sugeria.** Os dois
provedores foram conferidos contra a API de verdade antes de escrever o parser
— e o do Codex teve que ser reescrito depois da primeira versão, que seguia a
estrutura inferida do código compilado.

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

### A6 — Login OAuth para contas independentes
`AiQuota::ConnectClaude` (`app/services/ai_quota/connect_claude.rb`) faz o
handshake PKCE com o mesmo `client_id` público do Claude Code CLI que
`Refresh::Claude` já usa para renovar — aqui usado também para o passo de
autorização inicial. `redirect_uri` é a página hospedada da própria Anthropic
(não localhost): o usuário copia o `code#state` de lá e cola de volta na tela
de login do Orchestration.

Cada login cria uma conta **nova**, sempre `credential_source: "inline"` — não
existe (e não pode existir) uma variante que sobrescreva uma conta `file`
existente. `state == verifier` (não um valor aleatório separado, igual ao CLI
oficial) é validado antes de qualquer chamada de rede. O verifier vive só na
`session` do navegador entre a tela de login e a de colar o código, apagado no
uso — um único Puma, round-trip de poucos minutos, não precisa de nada
stateless.

Risco de ToS: reusar o `client_id` do CLI oficial para autorização (não só
refresh) é a mesma categoria de exposição que ferramentas de terceiros como o
9router já assumem — a Anthropic pode limitar ou revogar uso fora do CLI sem
aviso.

### A7 — Expansão de provedores (Antigravity & Ollama)
- **Antigravity CLI (`agy`)**: adota o arquivo `~/.gemini/antigravity-cli/antigravity-oauth-token` via `ImportLocal` (`credential_source: "file"`), mantendo a integridade da credencial do CLI local. Login OAuth interativo descartado por risco de ban ativo da Google sobre o reuso de client_ids de terceiros (fev/2026).
- **Ollama**: cadastro inline de `OLLAMA_API_KEY` (`credential_source: "inline"`) via formulário simples (`/ai_quota/ollama/key`), sem fluxo OAuth nem métricas de quota ao vivo (self-hosted).

## Verificação

Feita contra as APIs reais em 2026-09-01, não só com stub:

```
claude — pro — plano="Pro"
  Sessão (5h)    95/100  restante=5%   vermelho  reset 2026-09-01 13:20 UTC
  Semanal (7d)   62/100  restante=38%  amarelo   reset 2026-09-06 08:00 UTC
  extra: créditos 0,00 / 52,44 USD (desativado: out_of_credits)

codex — plano="Free"
  Mensal (30d)  100/100  restante=0%   vermelho  reset 2026-09-16 00:38 UTC
  extra: limite atingido, 0 créditos de reset
```

O token do Codex estava **expirado** (último refresh em 18/08) e a conta se
recuperou sozinha: o `Usage` detectou a expiração, chamou o refresher, gravou o
token novo de volta no arquivo do CLI e refez a leitura. É o caminho de
recuperação inteiro, exercitado de ponta a ponta.

Os testes cobrem o que não dá para checar à mão: rotação de refresh token,
escrita atômica, permissão 600, e que uma renovação falha não encoste no
arquivo.

## Fora de escopo

Provedores sem fetcher nesta fase (`kiro`, `qoder`, `zed`, `grok-cli`,
`ollama`, variantes `-cn`); login OAuth interativo para provedores além do
Claude (Codex e os demais continuam só import/renovação — ver A6); roteamento
e inferência (o Orchestration mostra quota, não vira gateway).
