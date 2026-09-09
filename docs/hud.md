# Orelhinha (HUD) — o resumo que o desktop lê

O painel responde "o que existe na infra?" quando alguém abre. A orelhinha
responde **"tem algo que eu preciso saber agora?"** sem ocupar uma aba: uma pill
preta soldada na borda direita da tela, três células, e o hover conta o resto.

Shell (Rust/Tauri, Windows): repo `redhusky-hud`. Contrato do JSON:
`00_docs/hud-contract.md` daquele repo. Aqui mora só o domínio.

## As três células

| célula | ícone | janelas |
|---|---|---|
| **Recursos** | `cpu` | Uptime · CPU · RAM · Disco · Swap |
| **Docker** | `server` | Stacks · Services · Images · Containers · Volumes · Networks |
| **Bancos** | `database` | Master · Replicas · Analytics · Rabbit · Backups · Deltas |

## Todo item tem um % com denominador real

Contador puro ("48 imagens") não diz se está bem ou mal. O que diz é a fração
contra um denominador que **o próprio sistema já define** — nada de régua
inventada:

| item | fração | de onde vem o denominador |
|---|---|---|
| CPU/RAM/Disco/Swap | uso ÷ 100 | cor sai do limiar que já dispara alerta no `MetricsJob` (85/90/80/50) |
| Uptime | tempo de pé ÷ 30d | janela de reboot: passar dela é kernel velho, amarelo, não incêndio |
| Stacks | stacks saudáveis ÷ total | serviço escalado a 0 está desligado de propósito, não conta como doente |
| Services | tarefas no ar ÷ desejadas | `ServiceStatus` do próprio Swarm |
| Images | imagens sem container ÷ total | desperdício de disco — enche a barra, nunca passa de amarelo |
| Containers | rodando ÷ total | idem |
| Volumes | em uso ÷ total | `RefCount` do `system df` |
| Networks | em uso ÷ total | referência de container/serviço; `bridge/host/none` nunca são órfãs |
| Master/Analytics | conexões ÷ `max_connections` | teto do próprio Postgres: estourar derruba aplicação |
| Replicas | em streaming ÷ esperadas | `pg_stat_replication`; o atraso vai na legenda |
| Rabbit | memória ÷ watermark | o ponto em que o broker **bloqueia publishers** |
| Backups | idade do último ÷ RPO 24h | responde "posso restaurar ontem?" |
| Deltas | corrente ÷ 6 | restore percorre a corrente inteira |

`progress` é a barra e `severity` é a cor, campos separados de propósito: 100%
de réplicas no ar é verde cheio, 92% de disco é vermelho cheio — mesmo número,
sentidos opostos, e quem sabe a diferença é o servidor, nunca a UI.

## Custo

O poll é de 15 segundos. As sondas são todas baratas (uma consulta, um GET) e o
`Internal::HudController` ainda guarda o payload por 30s. As duas caras ficam
**fora** do caminho da requisição:

- `wal-g` (sobe container aws-cli) → `BackupSnapshotJob`, diário, grava
  `deltas_since_full` na tabela; o HUD só lê a linha.
- `DbClusterInspectorService` (varre tabela por tabela) → não é usado aqui.

Fonte que falha é **omitida**, nunca zerada: zerar faria "fila vazia" e
"coletor quebrado" parecerem a mesma coisa.

## Autorizar uma máquina

Configurações → **Orelhinha (HUD)** → nome da máquina → *Gerar token*. Sai o
`config.json` pronto. O token aparece uma vez só (guardamos o digest), vale só
para leitura deste resumo, e revogar vale na requisição seguinte.

Endpoint: `GET /internal/hud`, `Authorization: Bearer <token>`.

## Rodar os testes

Não existe Postgres no host — o cluster é swarm-only. A receita:

```bash
cd platform-rails
S=/tmp   # onde guardar o env file
printf 'DATABASE_URL=postgresql://orchestration_test:%s@postgres-development:5432/orchestration_test\nRAILS_ENV=test\nSECRET_KEY_BASE=%s\n' \
  "$(cat .db_password_test)" "$(openssl rand -hex 32)" > $S/orch-test.env

docker run --rm --network postgres-cluster --env-file $S/orch-test.env \
  -v "$PWD:/app" -v /var/run/docker.sock:/var/run/docker.sock:ro \
  -w /app --entrypoint sh redhusk/orchestration:v0.9.100 -c '
    mkdir -p /tmp/stub/debug && echo "# stub" > /tmp/stub/debug/prelude.rb
    export RUBYLIB=/tmp/stub
    bin/rails test'
```

Três detalhes que custaram tempo para descobrir:

1. **A imagem de prod não traz a gem `debug`** (`BUNDLE_WITHOUT="development test"`),
   e `config/application.rb` faz `Bundler.require` do grupo `:test`. O stub vazio
   em `RUBYLIB` resolve sem rebuildar imagem.
2. **Conectar direto no `postgres-development`**, não pelo PgBouncer (porta 5436):
   o `auth_file` do bouncer não conhece o role de teste.
3. **O socket do Docker precisa estar montado**: 20 testes renderizam o layout,
   que chama `runtime_capabilities` no cliente real. Sem o socket, 20 erros que
   não têm nada a ver com o código sob teste.
4. **O role de teste é superusuário naquela instância** — fixtures usam
   `disable_referential_integrity`, que exige isso. É um Postgres só de teste;
   em prod continua valendo role dedicado sem privilégio.
