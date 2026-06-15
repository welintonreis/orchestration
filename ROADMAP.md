# Redhusk Orchestration — Roadmap de Implementação (Rails 8)

Stack final: Rails 8.1 + SQLite + excon + Hotwire + Tailwind + Solid Queue

---

## Fase 0 — Limpeza do repo

- [ ] Remover código Go: `main.go`, `internal/`, `go.mod`, `go.sum`, `node_modules/`, binários
- [ ] Manter: `deploy/`, `SPEC.md`, `ROADMAP.md`, `VERSION`, `.gitignore`
- [ ] Atualizar `.gitignore` para Rails
- [ ] Atualizar `.tool-versions` (ruby 3.3.x)

---

## Fase 1 — Scaffold Rails 8

```bash
rails new platform-rails \
  --database=sqlite3 \
  --asset-pipeline=propshaft \
  --skip-action-mailer \
  --skip-action-mailbox \
  --skip-action-text \
  --skip-active-storage \
  --skip-jbuilder \
  --skip-hotwire   # adicionar manualmente para controle
cd platform-rails
```

Gems a adicionar no Gemfile:
```ruby
gem "excon"                    # Docker API via Unix socket
gem "solid_queue"              # background jobs (métricas)
gem "solid_cache"              # cache
gem "solid_cable"              # ActionCable adapter
gem "turbo-rails"              # Hotwire Turbo
gem "stimulus-rails"           # Hotwire Stimulus
gem "tailwindcss-rails"        # CSS sem Node
gem "thruster"                 # HTTP/2 + static assets
```

- [ ] `rails generate authentication` — gera User, Session, controllers
- [ ] Adicionar campo `role` em User (admin/operator/readonly)
- [ ] Configurar Solid Queue como queue adapter
- [ ] Configurar Solid Cable como Action Cable adapter
- [ ] Configurar Solid Cache

---

## Fase 2 — Database + Models

Migrations:
- [ ] `users` — adicionar coluna `role` (padrão: admin para primeiro user)
- [ ] `environments` — name, endpoint_type, endpoint, active
- [ ] `alerts` — level, resource, message, read_at
- [ ] `host_metrics` — cpu/ram/disk/load floats + timestamps

Models:
- [ ] `Environment` — validações de endpoint (unix:// ou tcp://)
- [ ] `Alert` — scopes: unread, critical, by_resource
- [ ] `HostMetric` — scope: last_24h, latest

---

## Fase 3 — DockerClient Service

Arquivo: `app/services/docker_client.rb`

- [ ] Conexão via `excon` com Unix socket ou TCP
- [ ] Parser de stream multiplexado (8-byte header)
- [ ] `info` → Hash com system info
- [ ] `containers(all:)` → Array
- [ ] `container_start/stop/restart/kill/pause/unpause/remove`
- [ ] `images` → Array
- [ ] `image_remove(id, force:)`
- [ ] `volumes` → Array
- [ ] `volume_remove(name, force:)`
- [ ] `networks` → Array
- [ ] `network_remove(id)`
- [ ] `services` → Array (Swarm)
- [ ] `nodes` → Array (Swarm)
- [ ] `container_logs(id, tail:, &block)` — streaming com bloco
- [ ] `container_stats(id, &block)` — streaming stats

---

## Fase 4 — Auth + Setup Flow

- [ ] Customizar controller de registro (`registrations_controller.rb`)
- [ ] `/setup` — first-run: cria admin + environment "local" automático
- [ ] Guard: redireciona para `/setup` se 0 users
- [ ] Guard: redireciona para `/login` se não autenticado
- [ ] `before_action :require_authentication` no ApplicationController

---

## Fase 5 — Layout + Design System

- [ ] `application.html.erb` — dark theme base (bg-gray-950)
- [ ] Sidebar colapsável com Alpine.js
- [ ] Nav links com active state
- [ ] Header com slot para page title, actions, alert badge
- [ ] Partial `_alert_badge.html.erb`
- [ ] Tailwind config com safelist de classes dinâmicas
- [ ] Helpers: `status_color`, `percent_color`, `human_bytes`, `human_age`

---

## Fase 6 — Environments

- [ ] `EnvironmentsController` — index, new, create, destroy
- [ ] Teste de conectividade ao criar (`docker_client.info`)
- [ ] Cookie `active_env` — persiste ambiente selecionado
- [ ] `current_docker_client` helper no ApplicationController

---

## Fase 7 — Dashboard

- [ ] `DashboardController#index`
- [ ] Busca info, containers, images, volumes, networks (parallel requests ou sequential)
- [ ] Swarm stats se ativo
- [ ] Host metrics do último `HostMetric.last`
- [ ] Alertas não lidos

---

## Fase 8 — Containers

- [ ] `ContainersController` — index, logs
- [ ] `ContainerActionsController` — start, stop, restart, kill, pause, unpause, remove
- [ ] View index: tabela com status badge, portas, age, action buttons
- [ ] Filtro all/running via query param
- [ ] `LogsChannel` (ActionCable) — stream logs em tempo real
  - Client subscribe ao channel com container_id
  - Server abre `container_logs` stream e broadcast chunks
  - View: `<pre>` com auto-scroll via Stimulus

---

## Fase 9 — Images, Volumes, Networks

- [ ] `ImagesController` — index, destroy
- [ ] `VolumesController` — index, destroy  
- [ ] `NetworksController` — index, destroy
- [ ] Views: tabelas consistentes com container index
- [ ] Proteção: networks bridge/host/none não mostram botão remove

---

## Fase 10 — Swarm

- [ ] `Swarm::ServicesController` — index
- [ ] `Swarm::NodesController` — index
- [ ] View services: nome, imagem, mode, réplicas, leader badge
- [ ] View nodes: hostname, role, status badge, addr, engine version
- [ ] Guard: redireciona se Swarm não ativo

---

## Fase 11 — Host Metrics + Alerts

- [ ] `MetricsJob` (Solid Queue recurring, 30s)
  - Lê `/proc/stat` → CPU% (delta entre samples)
  - Lê `/proc/meminfo` → RAM%
  - `syscall` Statfs → Disk%
  - Lê `/proc/loadavg`
  - Salva `HostMetric.create`
  - Compara com thresholds → cria `Alert` se excedido
- [ ] `AlertsController` — index, mark_all_read
- [ ] View alerts: listagem com level badge, timestamp, mensagem
- [ ] Badge no layout header

---

## Fase 12 — Dockerfile + Deploy

- [ ] `platform-rails/Dockerfile` para Rails 8 production
  - Multi-stage: bundle install + assets precompile + final slim image
  - `./bin/thrust ./bin/rails server` como CMD
- [ ] Atualizar `deploy/orchestration.stack.yml`
  - Volumes: docker.sock, /proc, db, storage
  - Env: RAILS_MASTER_KEY, PROC_PATH, thresholds
- [ ] Atualizar `deploy/deploy-prod.sh` para apontar para `platform-rails/`
- [ ] `config/credentials.yml.enc` — gerar chave de produção
- [ ] Teste de deploy completo

---

## Fase 13 — Git Deploy Module

### Database
- [ ] Migration `CreateGitConnections` — name, repo_url, branch, auth_type, username, token_ciphertext, ssh_key_ciphertext, last_commit_sha, last_pulled_at
- [ ] Migration `CreateGitStacks` — environment_id, git_connection_id, name, compose_file, deploy_mode, status, last_deploy_output, last_deployed_at, webhook_token, auto_update, poll_interval

### Models
- [ ] `GitConnection` — validates url format, encrypts token + ssh_key (`encrypts :token` Rails 7.1+)
- [ ] `GitStack` — belongs_to connection + environment, `before_create :generate_webhook_token`, status enum

### Services
- [ ] `GitUnpacker` — clone/pull com suporte a none/token/ssh_key auth, retorna path do compose file
- [ ] `GitDeployer` — executa `docker stack deploy` ou `docker compose up` via `Open3.capture3`, atualiza status + output
- [ ] `GitPollService` — `git ls-remote` para checar SHA sem clone completo

### Jobs
- [ ] `GitDeployJob` — orquestra Unpacker → Deployer, broadcast output via Turbo Stream
- [ ] `GitAutoPollJob` — poll_interval via Solid Queue recurring por stack

### Controllers + Routes
- [ ] `GitConnectionsController` — CRUD + `POST :test`
- [ ] `GitStacksController` — CRUD + `POST :deploy` + `GET :show` (output stream)
- [ ] `Webhooks::DeploysController` — `POST /webhooks/:token/deploy`

### Views
- [ ] `/git_connections` — lista + test button
- [ ] `/git_stacks` — lista com status badges
- [ ] `/git_stacks/:id` — show com deploy output `<pre>`, commit SHA, webhook URL copiável
- [ ] Formulário: seleciona connection, compose_file, deploy_mode, auto_update toggle

---

## Ordem de execução sugerida

```
Fase 0 → 1 → 2 → 3 → 4+5 → 6 → 7 → 8 → 9 → 10 → 11 → 12 → 13
  ↑limpeza scaffold   ↑docker  ↑auth+ui  ↑envs  ↑dash  ↑features  ↑deploy  ↑git
```

Fases 4+5 paralelas (auth + layout não conflitam).
Fases 8-10 paralelas após Fase 7.
Fase 11 independente após Fase 2.
Fase 13 independente após Fase 7 (precisa de environments + dashboard base).

---

## Estado Atual — Fases 0-13 CONCLUÍDAS (Jun 2026)

**Branch:** `develop` em `gitlab.redhusky.com.br/redhusky/orchestration`
**Stack:** Rails 8.1.3, Ruby 3.3.11, Docker 29.5.3
**Deploy:** Build local → `docker stack deploy orchestration-prod`

### Bugs conhecidos / pendentes
- `Dockerfile` faltava `libyaml-dev` → psych falha no bundle install — **CORRIGIDO**
- Logs de container são estáticos (snapshot) — ActionCable streaming pendente (Fase 14)
- RBAC roles não enforced nos controllers — pendente (Fase v1.1)

---

## Fase 14 — ActionCable Logs Streaming (próxima)

Logs de container em tempo real via WebSocket.

### Arquitetura
```
ContainersController#logs → LogsChannel (ActionCable)
  Client subscribe: { container_id: "abc123", tail: 200 }
  Server: Thread abre DockerClient#container_logs(id) { |chunk| broadcast }
  View: Stimulus controller → append chunks ao <pre>, auto-scroll
```

### Implementação
- [ ] `app/channels/logs_channel.rb` — `subscribed` inicia thread de streaming; `unsubscribed` mata thread
- [ ] `app/javascript/controllers/log_stream_controller.js` — conecta ao canal, append chunks, auto-scroll
- [ ] Atualizar `app/views/containers/logs.html.erb` — trocar `<pre>` estático por Stimulus + Turbo Stream
- [ ] `config/cable.yml` — já usa Solid Cable (zero config extra)
- [ ] Thread safety: `@stream_thread` por connection, `ensure` fecha ao desconectar

### Notas técnicas
- `DockerClient#container_logs` com bloco já suporta streaming (implementado na Fase 3)
- ActionCable em produção via Solid Cable (SQLite) — sem Redis necessário
- Chunk demux já implementado no `DockerClient#demux_stream`

---

## Fase v1.1 — UX Polish + RBAC

### RBAC (Role-Based Access Control)
- [ ] `app/controllers/concerns/authorization.rb` — helpers `require_admin!`, `require_operator!`
- [ ] `ApplicationController` — include Authorization
- [ ] Enforcing por controller:
  - `ContainerActionsController` (stop/remove) → operator+
  - `ImagesController#remove` → operator+
  - `UsersController` → admin only
  - `EnvironmentsController` → admin only
  - `GitConnectionsController` → admin only
- [ ] Views — ocultar botões por role: `<% if current_user.admin? %>`

### Environment indicator
- [ ] Header: badge `[ENV: local ▾]` com dropdown Stimulus para trocar environment sem ir à página
- [ ] `ApplicationController#active_environment` já existe — só falta exibir no layout

### Search/Filter client-side
- [ ] Input "Filter by name" em containers/images/volumes — Stimulus controller filtra rows por `data-name`
- [ ] Sem request extra — puro JS no Stimulus

### Loading states
- [ ] Stimulus controller `loading` — adiciona spinner + disable em `button_to` após click
- [ ] `data-action="click->loading#start"` nos botões de ação

### Breadcrumbs
- [ ] Helper `breadcrumb(*items)` no ApplicationHelper
- [ ] `_breadcrumb.html.erb` partial no layout
- [ ] Uso: `breadcrumb("Containers", containers_path), ("Logs", nil)`

---

## Fase v1.2 — Container Stats Live

- [ ] `StatsChannel` (ActionCable) — broadcast stats JSON a cada 2s por container
- [ ] Stimulus `stats-controller.js` — atualiza CPU/MEM bars sem page reload
- [ ] `DockerClient#container_stats` já implementado com bloco de streaming
- [ ] View: mini progress bars CPU/MEM na tabela de containers (colunas extras)

---

## Fase v1.3 — Multi-user + Audit Log

### Users management
- [ ] Migration `add_active_to_users` — boolean active default true
- [ ] `UsersController` (admin only) — index, new, create, edit, update, destroy
- [ ] View: lista users com role badge, botão ativar/desativar
- [ ] Setup flow — já cria primeiro admin; segundo user só via admin

### Audit Log
- [ ] Migration `CreateAuditLogs` — user_id, action (string), target_type, target_id, metadata (json), ip_address
- [ ] `AuditLog` model — belongs_to user
- [ ] `Auditable` concern — `before_action :log_action` com ação inferida do controller#action
- [ ] `AuditLogsController` (admin only) — index com paginação, filtro por user/ação
- [ ] View: tabela paginada, timestamp, user email, ação, target

---

## Fase v1.4 — Métricas Históricas

- [ ] HostMetric já armazena 24h de dados — falta visualização
- [ ] SVG sparkline helper — gera `<polyline>` com pontos do `HostMetric.last_24h`
- [ ] Dashboard — adicionar sparklines nos metric bars (sem JS externo)
- [ ] Turbo Frame `<turbo-frame id="metrics" src="/metrics/latest" refresh="interval" data-interval="30000">` — auto-refresh
- [ ] `/metrics` endpoint — retorna fragment HTML com bars atualizadas

---

## Fase v2.0 — Advanced (futuro)

### Container exec (terminal web)
- Requer xterm.js (único caso justificando npm no projeto)
- Docker API: POST /exec/create → POST /exec/start → WebSocket hijack
- ActionCable bidirectional para I/O do terminal

### Notificações externas
- Alert model → campo `webhook_url` por tipo de threshold
- `AlertNotifierJob` — POST JSON ao webhook quando Alert criado (Slack/Discord/N8N)
- Config via env: `ALERT_WEBHOOK_URL`, `ALERT_WEBHOOK_SECRET`

### CI/CD automático
- GitLab webhook → POST /webhooks/:token/deploy já existe
- Adicionar: verificação de branch + pipeline status antes de deploy
- `GitConnection#ci_token` — token para consultar pipeline status na GitLab API

---

## Referências rápidas

**Dev local:**
```bash
cd platform-rails && bin/dev
```

**Deploy prod (build local):**
```bash
cd /root/docker/redhusk-orchestration
docker build --no-cache -t orchestration:v0.2.0 platform-rails/
IMAGE=orchestration:v0.2.0 \
  RAILS_MASTER_KEY=$(cat platform-rails/config/master.key) \
  docker stack deploy -c deploy/orchestration.stack.yml --with-registry-auth orchestration-prod
docker service update --force --detach orchestration-prod_web
```

**Testar DockerClient:**
```ruby
rails runner "c = DockerClient.new; puts c.info['ServerVersion']"
```

**Testar MetricsJob:**
```ruby
rails runner "MetricsJob.new.perform; puts HostMetric.latest.inspect"
```

**Git:**
```
remote: https://gitlab.redhusky.com.br/redhusky/orchestration.git
branch develop → staging (orchestration-dev.redhusky.com.br)
branch main    → prod    (orchestration.redhusky.com.br)
```

---

## Referências rápidas

**Iniciar dev:**
```bash
cd platform-rails
bin/dev  # Procfile.dev: rails + tailwind watch
```

**Testar DockerClient:**
```ruby
# rails console
c = DockerClient.new(endpoint: "unix:///var/run/docker.sock")
c.info
c.containers(all: true).first
```

**Deploy prod:**
```bash
bash deploy/deploy-prod.sh
```
