# Redhusk Orchestration — Project Spec

## Overview

Custom Docker & Docker Swarm management platform. Feature-comparable to Portainer,
built from scratch para controle interno, branding e extensibilidade.

**Decisões arquiteturais fechadas:**
- Serviço standalone (não plugin do HuskyOS) — deploy independente, sem acoplamento
- Stack Rails 8 — mesma stack do HuskyOS, máxima produtividade
- Docker API via `excon` + parser customizado — sem gem docker-api, sem Python/Go sidecar
- SQLite + Solid Queue/Cache/Cable — zero-ops, mesmo padrão HuskyOS

---

## Tech Stack

| Camada | Tecnologia | Razão |
|---|---|---|
| Framework | Rails 8.1 (monolito) | Produtividade, Hotwire nativo, mesma stack HuskyOS |
| Auth | `rails generate authentication` | has_secure_password, sessions table, pronto |
| Banco | SQLite 3 | Zero-ops, suficiente para metadados locais |
| Jobs | Solid Queue | Métricas de host a cada 30s, sem Redis |
| Cache | Solid Cache | Padrão HuskyOS |
| WebSocket | Action Cable (Solid Cable) | Streaming logs em tempo real |
| Front | Hotwire (Turbo + Stimulus) + Tailwind | SSR, sem build JS pesado |
| Docker API | `excon` gem + parser customizado | Unix socket direto, latência ~0.3ms, streaming completo |
| CSS | `tailwindcss-rails` gem | Build integrado, sem Node separado |
| Assets | Propshaft | Rails 8 padrão |
| Icons | `lucide-rails` ou SVG inline | Consistente com HuskyOS |
| Deploy | Docker Swarm + Traefik | redhusky-lab-01, mesmo cluster HuskyOS |

---

## Docker Client — Arquitetura

```
Rails Service (DockerClient)
  │
  │  excon (Unix socket)
  ▼
/var/run/docker.sock
  │
  ▼
Docker daemon REST API v1.47
```

### Streaming demux

Docker multiplica stdout/stderr num único stream com header 8 bytes:

```
[stream_type: 1B][padding: 3B][size: 4B big-endian][payload: size bytes]
stream_type: 0=stdin 1=stdout 2=stderr
```

O `DockerClient` parseia isso e entrega chunks limpos para o ActionCable/SSE.

### Interface do DockerClient

```ruby
# app/services/docker_client.rb
client = DockerClient.new(endpoint: "unix:///var/run/docker.sock")

# Ops pontuais
client.info                           # → Hash (system info)
client.containers(all: true)          # → Array<Hash>
client.container_start(id)
client.container_stop(id)
client.container_restart(id)
client.container_remove(id, force: false)
client.images                         # → Array<Hash>
client.image_remove(id, force: false)
client.volumes                        # → Array<Hash>
client.volume_remove(name, force: false)
client.networks                       # → Array<Hash>
client.network_remove(id)
client.services                       # → Array<Hash>
client.nodes                          # → Array<Hash>

# Streaming (bloco por chunk)
client.container_logs(id, tail: 200) { |chunk| broadcast(chunk) }
client.container_stats(id)           { |stat|  broadcast(stat)  }
```

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│           Browser (Hotwire / Turbo Frames + Cable)       │
└────────────────────────┬────────────────────────────────┘
                         │ HTTPS + WebSocket
┌────────────────────────▼────────────────────────────────┐
│                  Rails 8 (Puma + Thruster)               │
│                                                          │
│  Controllers → DockerClient (excon) → Docker daemon     │
│  Solid Queue → MetricsJob → /proc → AlertsTable         │
│  Action Cable → LogsChannel → streaming logs            │
└──────────────────────────────────────────────────────────┘
                         │
                   Unix socket
                         │
                    Docker daemon
```

---

## Features — v1

### Auth
- `rails generate authentication` — sessions, has_secure_password
- First-run `/setup` — cria primeiro admin, cria environment "local" automático
- Roles: admin / operator / readonly
- Cookie session (não JWT)

### Environments
- CRUD de endpoints Docker (unix socket ou tcp)
- Environment ativo via cookie `active_env`
- Teste de conectividade ao criar
- Environment "local" criado no setup

### Dashboard
- Contadores: containers, images, volumes, networks, services, nodes
- Host metrics: CPU%, RAM%, Disk% com barras coloridas
- Docker version + Swarm status
- Alertas recentes

### Containers
- Listagem com filtro (todos / só rodando)
- Status badge colorido (running/paused/exited/restarting)
- Ações: start, stop, restart, kill, pause, unpause, remove
- Logs em tempo real via Action Cable (Turbo Stream)
- Tail configurável: 100 / 500 / 1000 linhas

### Images
- Listagem com tags, size, age
- Remove (com force option)

### Volumes
- Listagem com driver, mountpoint
- Remove

### Networks
- Listagem com driver, scope
- Remove (protege bridge/host/none)

### Swarm
- Services: nome, imagem, mode, réplicas
  - Ações por linha: Scale −1, Scale +1, Forçar Atualização (strip digest + ForceUpdate counter → re-pull)
  - Bulk: Scale −1 / +1 via checkbox seleção
- Nodes: hostname, role, status, addr, engine version
- Leader badge
- Topology: mapa visual nós → stacks → serviços → containers
  - Filtro client-side: Ativo / Ambos / Inativo (cascata: oculta tasks/serviços/stacks sem itens no filtro)
  - Filtro persiste via `sessionStorage` através de auto-reloads (Turbo visit)

### Images
- Paginação por repositório (não por imagem individual) — evita discrepância entre contagem e linhas visíveis
- Agrupamento tag-dropdown por repo no client-side
- Label: X repositórios · Y imagens

### Containers — Logs
- Streaming em tempo real via ActionCable (LogsChannel)
- Auto-scroll: desliga automaticamente ao rolar para cima, religa ao voltar ao fundo
- Botão toggle visual (cyan = ON, cinza = OFF)
- Filtro de texto client-side sobre linhas recebidas

### Host Metrics (Solid Queue job)
- `MetricsJob` a cada 30s via Solid Queue recurring
- Lê `/proc/stat` (CPU delta), `/proc/meminfo` (RAM), `/proc/loadavg`, `syscall` (disk)
- `PROC_PATH` env var: `/proc` local, `/host/proc` em container
- Thresholds via env: `CPU_THRESHOLD=85`, `RAM_THRESHOLD=90`, `DISK_THRESHOLD=80`
- Insere `Alert` quando threshold excedido
- Badge de alertas não lidos no header

### Alerts
- Tabela `alerts`: level (warning/critical), resource (cpu/ram/disk), message, read_at
- Badge no layout com count não lidos
- Página `/alerts` com listagem + marcar como lido

---

## Database Schema

```ruby
# users
t.string :email_address, null: false, index: unique   # gerado pelo rails auth
t.string :password_digest, null: false
t.string :role, default: 'readonly'
t.timestamps

# sessions (gerado pelo rails auth)
t.belongs_to :user
t.string :ip_address
t.string :user_agent
t.datetime :expires_at
t.timestamps

# environments
t.string :name, null: false
t.string :endpoint_type, default: 'socket'   # socket | tcp
t.string :endpoint, null: false
t.boolean :active, default: true
t.timestamps

# alerts
t.string :level, null: false          # warning | critical
t.string :resource, null: false       # cpu | ram | disk
t.string :message, null: false
t.datetime :read_at
t.timestamps

# host_metrics (últimas 24h para gráficos futuros)
t.float :cpu_percent
t.float :ram_percent
t.integer :ram_used_mb
t.integer :ram_total_mb
t.float :disk_percent
t.float :disk_used_gb
t.float :disk_total_gb
t.float :load_avg_1
t.float :load_avg_5
t.float :load_avg_15
t.timestamps
```

---

## Infra

```
Host:    redhusky-lab-01 (167.86.110.111)
Cluster: Docker Swarm single-node
Proxy:   Traefik v3.6

Ambientes:
  dev  → branch develop → orchestration-dev.redhusky.com.br
  prod → branch main    → orchestration.redhusky.com.br (deploy manual)

Registry: registry.gitlab.redhusky.com.br
CI/CD: deploy manual local (deploy-prod.sh)
```

## Deploy Stack

```yaml
# deploy/orchestration.stack.yml
services:
  web:
    image: ${IMAGE}
    environment:
      RAILS_ENV: production
      RAILS_MASTER_KEY: ${RAILS_MASTER_KEY}
      PROC_PATH: /host/proc
      CPU_THRESHOLD: 85
      RAM_THRESHOLD: 90
      DISK_THRESHOLD: 80
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - /proc:/host/proc:ro
      - orchestration-data:/rails/db
      - orchestration-storage:/rails/storage
    deploy:
      labels:
        - "traefik.enable=true"
        - "traefik.http.routers.orchestration-prod.rule=Host(`orchestration.redhusky.com.br`)"
        - "traefik.http.routers.orchestration-prod.entrypoints=websecure"
        - "traefik.http.routers.orchestration-prod.tls.certresolver=letsencrypt"
        - "traefik.http.services.orchestration-prod.loadbalancer.server.port=80"
    networks:
      - traefik
```

---

## Dockerfile (Rails 8 padrão)

```dockerfile
FROM ruby:3.3-slim AS base
RUN apt-get update && apt-get install -y build-essential libsqlite3-dev curl
WORKDIR /rails

FROM base AS deps
COPY Gemfile Gemfile.lock ./
RUN bundle install --deployment --without development test

FROM base AS final
COPY --from=deps /rails/vendor/bundle /rails/vendor/bundle
COPY . .
RUN bundle exec rails assets:precompile
EXPOSE 80
CMD ["./bin/thrust", "./bin/rails", "server"]
```

---

## Git Deploy Module

Deploy de stacks diretamente de repositórios Git — equivalente ao GitOps deploy do Portainer.

### Fluxo

```
GitConnection (credenciais)
      │
      ▼
GitUnpacker (clone/pull → tmp/)
      │
      ▼
GitDeployer (docker stack deploy / compose up)
      │
      ▼
GitStack (status, output, last_commit_sha)
```

### Models

```ruby
# git_connections — credenciais de acesso ao repo
t.string :name, null: false
t.string :repo_url, null: false
t.string :branch, default: 'main'
t.string :auth_type, default: 'none'   # none | token | ssh_key
t.string :username                      # para token auth
t.string :token_ciphertext             # Rails encrypted_attribute
t.text   :ssh_key_ciphertext           # Rails encrypted_attribute
t.string :last_commit_sha
t.datetime :last_pulled_at
t.timestamps

# git_stacks — define um deploy
t.belongs_to :environment, null: false
t.belongs_to :git_connection, null: false
t.string :name, null: false            # nome do stack/compose
t.string :compose_file, default: 'docker-compose.yml'
t.string :deploy_mode, default: 'swarm_stack'  # swarm_stack | compose
t.string :status, default: 'idle'     # idle | deploying | deployed | failed
t.text   :last_deploy_output
t.datetime :last_deployed_at
t.string :webhook_token                # hex aleatório — POST /webhooks/:token/deploy
t.boolean :auto_update, default: false
t.integer :poll_interval, default: 300  # segundos entre checks de commit
t.timestamps
```

### Services

**`GitUnpacker`** — clona/atualiza repo em `tmp/git_repos/<connection_id>/`
- auth_type `none`: git clone direto
- auth_type `token`: embed `https://<user>:<token>@<host>/...`
- auth_type `ssh_key`: escreve chave em `tmp/git_keys/<id>`, usa `GIT_SSH_COMMAND`
- Retorna path absoluto para o compose_file dentro do repo
- Captura `last_commit_sha` via `git rev-parse HEAD`

**`GitDeployer`** — executa o deploy com `Open3.capture3`
- `swarm_stack`: `docker stack deploy --compose-file <path> --with-registry-auth <name>`
- `compose`: `docker compose -f <path> up -d --remove-orphans`
- Atualiza `status`, `last_deploy_output`, `last_deployed_at` no `GitStack`
- Cria `Alert` level: critical se falhar

**`GitPollService`** — verifica novo commit sem clonar
- `git ls-remote <repo> refs/heads/<branch>` → SHA em 1s
- Compara com `last_commit_sha` → aciona deploy só se mudou

### Jobs

```ruby
# GitDeployJob — executa um deploy completo
class GitDeployJob < ApplicationJob
  def perform(git_stack_id)
    stack = GitStack.find(git_stack_id)
    stack.update!(status: "deploying")
    path = GitUnpacker.call(stack.git_connection)
    GitDeployer.call(stack, compose_path: path)
  end
end

# GitAutoPollJob — recurring via Solid Queue (per poll_interval)
class GitAutoPollJob < ApplicationJob
  def perform(git_stack_id)
    stack = GitStack.find(git_stack_id)
    return unless stack.auto_update?
    new_sha = GitPollService.call(stack.git_connection)
    return if new_sha == stack.git_connection.last_commit_sha
    GitDeployJob.perform_later(git_stack_id)
  end
end
```

### Controllers

- `GitConnectionsController` — CRUD + `POST #test` (valida acesso ao repo)
- `GitStacksController` — CRUD + `POST #deploy` (trigger manual) + `GET #show` (output em tempo real via Turbo Stream)
- `Webhooks::DeploysController` — `POST /webhooks/:token/deploy` → sem auth, token na URL, 200 imediato + async job

### Segurança

- Tokens e SSH keys armazenadas com `attr_encrypted` ou `encrypts :token` (Rails 7.1+)
- Webhook token: 32 bytes hex gerado no `before_create`
- SSH keys escritas em arquivo com `chmod 600`, deletadas após uso
- `GIT_TERMINAL_PROMPT=0` para falhar rápido em lugar de travar
- Diretório `tmp/git_repos/` no `.gitignore`

### UI

- `/git_connections` — lista conexões, badge de status, botão "Test Connection"
- `/git_stacks` — lista stacks com status badge (idle/deploying/deployed/failed)
- `/git_stacks/:id` — show: output do último deploy em `<pre>` com auto-scroll, botão Deploy Manual, badge commit SHA, webhook URL copiável
- `/git_stacks/new` — form: seleciona connection, define nome, compose_file, deploy_mode, auto_update

---

## Layout e UI

- Dark theme: `bg-gray-950` base, `bg-gray-900` cards, `bg-gray-800` borders
- Sidebar colapsável (Alpine.js)
- Header com page title + actions slot + alert badge
- Tabelas com hover, status badges coloridos
- Progress bars para métricas (verde/amarelo/vermelho por threshold)
- Tailwind CSS gerado via `tailwindcss-rails` (sem Node separado)
