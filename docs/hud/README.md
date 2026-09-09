# Notch (HUD) — o resumo que o desktop lê

O painel responde *"o que existe na infra?"* — mas só quando alguém abre. O
**Notch** responde **"tem algo que eu preciso saber agora?"** sem ocupar uma
aba: uma pill preta soldada na borda direita da tela, três células, e o hover
conta o resto.

```
PILL   = consciência        HOVER  = contexto
CLIQUE = abre o painel      PAINEL = investigação
```

O shell (Rust/Tauri, Windows) vive no repo **`redhusky-hud`**; o contrato do
JSON é o `00_docs/hud-contract.md` de lá. Aqui mora só o domínio: o que é uma
métrica boa, o que é uma métrica ruim, e de onde sai cada número.

---

## 1. As três células

| célula | ícone | janelas do card |
|---|---|---|
| **Recursos** | `cpu` | Uptime · CPU · RAM · Disco · Swap |
| **Docker** | `server` | Stacks · Services · Images · Containers · Volumes · Networks |
| **Bancos** | `database` | Master · Replicas · Analytics · Rabbit · Backups · Deltas |

Cada célula tem um anel (o `progress`) e uma cor (a `severity`). O anel mostra o
item mais apertado da célula; o card abre item por item.

---

## 2. Todo indicador é um % com denominador real

Esta é a regra que dá valor ao Notch. Contador puro — *"48 imagens"*, *"119
volumes"* — **não diz se está bem ou mal**. O que diz é a fração contra um
denominador, e o denominador foi buscado onde o **próprio sistema já o define**.
Nada de régua inventada.

### Recursos

| item | fração (`progress`) | cor (`severity`) | origem do número |
|---|---|---|---|
| **Uptime** | tempo de pé ÷ 30d | 0, ou 0.5 passando de 30d | `/proc/uptime`. A janela de 30 dias é de *reboot*: passar dela quer dizer kernel velho, o que é lembrete, não incêndio — por isso a cor para no amarelo |
| **CPU** | uso ÷ 100 | uso ÷ **85%** | `HostMetric` (job de métricas, `/proc/stat`). O limiar é o **mesmo** que já dispara alerta no `MetricsJob` |
| **RAM** | uso ÷ 100 | uso ÷ **90%** | `HostMetric` (`/proc/meminfo`, `MemAvailable`) |
| **Disco** | uso ÷ 100 | uso ÷ **80%** | `HostMetric` (partição raiz) |
| **Swap** | uso ÷ 100 | uso ÷ **50%** | `HostMetric`. Swap alto é sintoma de RAM curta, por isso o limiar é o mais severo |

> **Uma régua só.** Os limiares saem de `MetricsJob::CPU_THRESHOLD` e irmãos —
> os mesmos que geram `Alert` no painel. Se o Notch tivesse limiar próprio, ele
> viraria uma segunda opinião sobre a mesma máquina, e duas réguas discordando é
> pior que nenhuma.

### Docker

| item | fração | cor | origem |
|---|---|---|---|
| **Stacks** | stacks saudáveis ÷ total | fora ÷ total | `/services` agrupado por `com.docker.stack.namespace`. Saudável = todos os serviços com `RunningTasks >= DesiredTasks`. **Serviço escalado a 0 está desligado de propósito** e não conta como doente |
| **Services** | tarefas no ar ÷ desejadas | faltando ÷ desejadas | `ServiceStatus.RunningTasks` / `DesiredTasks`, do próprio Swarm (`/services?status=1`) |
| **Images** | imagens sem container ÷ total | idem, teto 0.6 | `/system/df`. Mede **desperdício**: imagem sem container é disco esperando um prune |
| **Containers** | rodando ÷ total | parados ÷ total, teto 0.6 | `/containers/json?all=1`, campo `State` |
| **Volumes** | em uso ÷ total | órfãos ÷ total, teto 0.6 | `/system/df`, `UsageData.RefCount` |
| **Networks** | em uso ÷ total | ociosas ÷ total, teto 0.6 | a listagem `/networks` **não** traz containers (só o inspect traz), então "em uso" sai do que containers e serviços referenciam. `bridge`, `host` e `none` são do Docker e nunca são órfãs |

> **Lixo não é incidente.** Images, Containers, Volumes e Networks têm a
> severidade limitada a 0.6 (amarelo): 99 volumes órfãos merecem uma faxina, não
> um susto no meio da madrugada. Só convergência (Stacks e Services) chega ao
> vermelho.

### Bancos

| item | fração | cor | origem |
|---|---|---|---|
| **Master** | conexões ÷ `max_connections` | ÷ 90% do teto | `pg_stat_activity` no `postgres-master`. É o teto que o **próprio Postgres** define: estourá-lo derruba aplicação |
| **Replicas** | em streaming ÷ esperadas | faltando ÷ esperadas | `pg_stat_replication`. Esperadas é **constante** (1, o `postgres-read`), e não "o que estiver conectado agora" — o objetivo é justamente notar quando uma some. O atraso de replay vai na legenda |
| **Analytics** | conexões ÷ `max_connections` | ÷ 90% do teto | idem, no `postgres-analytics` |
| **Rabbit** | memória ÷ watermark | ÷ 80% do watermark | `/api/nodes` da management API. O watermark é o ponto em que o broker **bloqueia publishers** — o limite mais honesto que existe para "o Rabbit está bem?". Mensagens e filas vêm do `/api/overview` e vão na legenda |
| **Backups** | idade do último ÷ **RPO 24h** | idem | `BackupSnapshot` (job diário). Responde literalmente *"consigo restaurar ontem?"*. Erro do wal-g = vermelho direto |
| **Deltas** | corrente ÷ 6 | idem | `deltas_since_full` do mesmo snapshot. Restore percorre a corrente **inteira**: quanto mais longa, mais demorado voltar |

---

## 3. `progress` é a barra, `severity` é a cor

São campos separados de propósito, e a distinção é o coração do contrato:

```
100% de réplicas no ar  →  barra cheia, VERDE
 92% de disco usado     →  barra cheia, VERMELHA
```

Mesmo número, sentidos opostos. Quem sabe a diferença é o **servidor**, que
conhece o domínio; a UI só lê a rampa de cor e nunca interpreta. Sem isso, um
SLA de 98,7% (alto = ótimo) sairia pintado igual a uma quota 98% consumida
(alto = péssimo).

Rampa (definida no shell, não aqui):

```
severity >= 0.8  →  #FF3F00  crítico
severity >= 0.5  →  #F2FF00  atenção
senão            →  #00FF88  ok
```

---

## 4. Custo: o poll é de 15 segundos

Toda sonda desta página é barata — uma consulta, um GET — e o
`Internal::HudController` ainda guarda o payload por 30s. As duas caras ficam
**fora** do caminho da requisição:

| coleta cara | onde roda | o que o Notch lê |
|---|---|---|
| `wal-g backup-list` (sobe um container `aws-cli`) | `BackupSnapshotJob`, diário às 3h10 | a linha de `BackupSnapshot`, incluindo `deltas_since_full` |
| `DbClusterInspectorService` (varre tabela por tabela) | tela de Cluster, sob demanda | **não é usado aqui** |

**Fonte que falha é omitida, nunca zerada.** Zerar faria "fila vazia" e "coletor
quebrado" parecerem a mesma coisa; omitir deixa o shell manter a última leitura
boa e escurecer a célula quando ela envelhece (`stale_after`).

Por isso a célula **Deltas** só aparece depois da primeira execução do job
posterior à migration — antes disso não há leitura, e inventar um zero seria
mentir.

---

## 5. Autorizar uma máquina

**Configurações → Notch (HUD)** → nome da máquina → *Gerar token*. Sai o
`config.json` pronto para colar em `%APPDATA%\RedHuskyHUD\config.json`.

- o token aparece **uma vez só** (guardamos o digest, como no `EdgeNode`);
- vale **só** para ler este resumo — nada de Docker, exec, scale ou qualquer
  coisa administrativa passa por ele;
- revogar vale na requisição seguinte;
- a coluna *Último contato* mostra se aquela máquina ainda fala com a gente.

Endpoint: `GET /internal/hud`, `Authorization: Bearer <token>`.

```json
{
  "schema_version": 1,
  "fetched_at": 1788890000,
  "stale_after": 300,
  "cells": [ { "id": "resources", "icon": "cpu", "label": "Recursos",
               "progress": 0.83, "severity": 1.0, "windows": [ ... ] } ]
}
```

Um binário serve N produtos: a mesma pill mostra HuskyOS e orchestration juntos,
basta uma segunda fonte no `config.json` do HUD.

---

## 6. Onde cada peça mora

| arquivo | papel |
|---|---|
| `app/services/hud_payload_service.rb` | as três células e todos os denominadores |
| `app/controllers/internal/hud_controller.rb` | endpoint máquina-a-máquina, Bearer + cache de 30s |
| `app/models/hud_device.rb` | dispositivo autorizado (digest do token, revogação) |
| `app/controllers/settings/hud_controller.rb` + `app/views/settings/hud/` | a tela que emite e revoga |
| `app/jobs/backup_snapshot_job.rb` | grava a corrente de deltas junto do snapshot diário |
| `test/services/hud_payload_service_test.rb` | trava as frações e as severidades, item por item |
| `test/controllers/internal/hud_controller_test.rb` | 401 sem token, 401 revogado, contrato no 200 |
| `test/controllers/settings/hud_controller_test.rb` | a tela que emite o token não pode cair |

---

## 7. Rodar os testes

Não existe Postgres no host — o cluster é swarm-only. O banco de teste é o
`orchestration_test` no **postgres-development** (role dedicado; senha em
`platform-rails/.db_password_test`, git-ignored):

```bash
cd platform-rails
S=/tmp
printf 'DATABASE_URL=postgresql://orchestration_test:%s@postgres-development:5432/orchestration_test\nRAILS_ENV=test\nSECRET_KEY_BASE=%s\n' \
  "$(cat .db_password_test)" "$(openssl rand -hex 32)" > $S/orch-test.env

docker run --rm --network postgres-cluster --env-file $S/orch-test.env \
  -v "$PWD:/app" -v /var/run/docker.sock:/var/run/docker.sock:ro \
  -w /app --entrypoint sh redhusk/orchestration:v0.9.100 -c '
    mkdir -p /tmp/stub/debug && echo "# stub" > /tmp/stub/debug/prelude.rb
    export RUBYLIB=/tmp/stub
    bin/rails test'
```

Quatro detalhes que custaram tempo para descobrir — mexer neles quebra tudo de
novo:

1. **Conectar direto no `postgres-development:5432`** pela rede
   `postgres-cluster`, e **não** pela porta 5436 (PgBouncer): o `auth_file` do
   bouncer não conhece o role de teste.
2. **A imagem de prod não traz a gem `debug`** (`BUNDLE_WITHOUT="development test"`)
   e `config/application.rb` faz `Bundler.require` do grupo `:test`. O stub vazio
   no `RUBYLIB` resolve sem rebuildar imagem.
3. **Montar `/var/run/docker.sock`**: 20 testes renderizam o layout, que chama
   `runtime_capabilities` no cliente Docker real. Sem o socket, 20 erros que não
   têm nada a ver com o código sob teste.
4. **O role de teste é superusuário naquela instância** — fixtures usam
   `disable_referential_integrity`. Vale só ali: é um Postgres de teste, e em
   prod continua role dedicado sem privilégio.

O `template1` do postgres-development já traz `pg_trgm` e `vector`, então um
`schema.rb` regenerado vem com um `enable_extension "pg_trgm"` que nenhuma
migration declara — tirar antes de commitar.

---

## 8. O que o Notch mostrou no primeiro dia

Não é anedota: é o argumento de existir. Assim que subiu em produção, com dados
reais, apareceu o que ninguém estava olhando:

- **Swap em 83%** (alerta em 50%) — a máquina está trocando pesado;
- **99 volumes órfãos ocupando 100,3GB**, com disco em 68%;
- **último backup com 6d 21h** — RPO de 24h estourado sete vezes;
- **12.491 mensagens em 24 filas** no Rabbit (memória tranquila, fila enchendo).

Nenhum desses números é novo no sistema. O que faltava era um lugar onde eles
tivessem denominador e cor.
