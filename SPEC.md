# Redhusk Orchestration — Project Spec

## Overview

Custom Docker & Docker Swarm management platform. Feature-comparable to Portainer,
built from scratch for internal control, branding, and extensibility.

**Goals:**
- Manage single-host Docker AND Swarm clusters from one UI
- REST API-first, UI as thin client
- Multi-environment support (multiple Docker endpoints)
- Role-based access control
- Audit log for all mutations

**Non-goals for v1:**
- Kubernetes support
- Plugin marketplace
- Edge agents / remote tunneling
- Billing / multi-tenant SaaS

---

## Tech Stack

Mesma stack do HuskyOS (husky-core) — sem desvio.

| Camada      | Tecnologia             | Razão                                           |
|-------------|------------------------|-------------------------------------------------|
| Framework   | Rails 8.1 (monolito)   | Full-stack, sem serviço Go separado             |
| Linguagem   | Ruby 3.3+              | Mesmo ecossistema do HuskyOS                    |
| Banco       | SQLite 3               | Zero-ops, suficiente para metadados locais      |
| Jobs        | Solid Queue            | Sem Redis, mesmo padrão HuskyOS                 |
| Cache       | Solid Cache            | Idem                                            |
| WebSocket   | Solid Cable            | Streaming logs/stats via ActionCable            |
| Front       | Hotwire (Turbo + Stimulus) + Tailwind + ViewComponent | SSR, sem build JS |
| Docker API  | `docker-api` gem       | Cliente Ruby para Docker REST API               |
| Auth        | `has_secure_password`  | Rails 8 auth generator, bcrypt                  |
| Autorização | Pundit                 | Mesmo padrão HuskyOS                            |
| Audit       | paper_trail            | Versionamento de mutations                      |
| Icons       | rails_icons (Lucide)   | Mesmos ícones do HuskyOS                        |
| CI/CD       | GitLab self-hosted     | `gitlab.redhusky.com.br`                        |
| Registry    | GitLab Container Registry | `registry.gitlab.redhusky.com.br`            |
| Deploy      | Docker Swarm + Traefik | `redhusky-lab-01` (mesmo cluster HuskyOS)       |

---

## Architecture

Rails full-stack — sem serviço separado. Chama Docker API diretamente via `docker-api` gem.

```
┌──────────────────────────────────────────────────────┐
│              Browser (Hotwire / Turbo Frames)         │
└─────────────────────────┬────────────────────────────┘
                          │ HTTPS (HTML + Turbo Streams)
                          │ ActionCable WebSocket (logs/stats)
┌─────────────────────────▼────────────────────────────┐
│                Rails 8 (Thruster + Puma)              │
│                                                        │
│  Controllers → Pundit policies → Services             │
│  paper_trail audit  │  Solid Queue jobs               │
│                      │                                 │
│  ┌───────────────────▼──────────────────────────────┐ │
│  │          DockerService (docker-api gem)           │ │
│  │  Wraps Docker::Container / Image / Volume / etc. │ │
│  │  + EnvironmentManager (troca de endpoint)        │ │
│  └──────────┬─────────────────────┬─────────────────┘ │
└─────────────┼─────────────────────┼─────────────────── ┘
              │                     │
  ┌───────────▼──┐       ┌──────────▼──────────┐
  │ Local Docker │       │  Remote Docker       │
  │ /var/run/    │       │  tcp:// + TLS        │
  │ docker.sock  │       │                      │
  └──────────────┘       └──────────────────────┘
```

---

## Feature Spec

### 1. Environments

- Add/remove Docker endpoints (local socket, TCP/TLS, SSH tunnel)
- Health check each endpoint on registration and on poll (30s interval)
- Per-environment resource summary (containers, images, volumes, networks)
- Switch active environment in UI without page reload

### 2. Containers

- List with filters: status (running/stopped/paused/dead), name, image, label
- Start / Stop / Restart / Pause / Unpause / Kill / Remove (with volume option)
- Inspect: full JSON + formatted view (ports, mounts, env, labels, network)
- Logs: streaming via SSE, tail N lines, follow toggle, search/filter
- Exec: interactive terminal via WebSocket (xterm.js)
- Stats: live CPU%, memory usage/limit, net I/O, block I/O via SSE
- Rename container
- Duplicate (create new container from same image + config)

### 3. Images

- List: name, tag, size, created, in-use indicator
- Pull from registry (with auth for private)
- Remove (force option, prune dangling)
- Inspect: layers, history, config
- Tag image
- Export / Import (tarball)
- Prune unused images

### 4. Volumes

- List: name, driver, mount point, size (if available), in-use indicator
- Create: name, driver, driver options, labels
- Inspect: full config + which containers use it
- Remove / bulk remove unused (prune)
- Browse volume contents (read-only file browser via temp container)

### 5. Networks

- List: name, driver, scope, subnet, gateway, attached containers
- Create: name, driver (bridge/overlay/macvlan), IPAM config, options, labels
- Inspect: full config + connected containers
- Connect / disconnect containers
- Remove / prune unused

### 6. Stacks (Compose)

- List stacks with service count and status
- Deploy new stack: paste compose YAML or upload file
- Update stack: edit compose inline, redeploy
- Remove stack (with optional volume removal)
- Download stack compose file
- Stack status: per-service running/desired replicas

### 7. Swarm Services

- List: name, image, mode (replicated/global), replicas, ports, updated
- Create service: full spec (image, replicas, ports, env, mounts, constraints,
  resource limits, update/rollback policy, labels)
- Update: scale, image update (rolling), env changes
- Rollback service
- Inspect: full spec + task list
- Logs: aggregate logs across tasks via SSE
- Remove service

### 8. Swarm Nodes

- List: hostname, role (manager/worker), status, availability, engine version
- Inspect: full node spec + task list
- Update: availability (active/pause/drain), role promotion/demotion, labels
- Remove node

### 9. Swarm Configs & Secrets

- List configs and secrets (secret values never returned after creation)
- Create config/secret from text or file upload
- Inspect config (value shown on creation only for secrets)
- Remove config/secret
- View which services reference each config/secret

### 10. Registries

- Add private registry (URL, auth)
- Test connectivity
- List repositories and tags (if registry API v2)
- Use registry for pull/push operations

### 11. Users & RBAC

```
Roles:
  admin      - full access to all environments and settings
  operator   - create/update/delete resources; no user management
  readonly   - read-only access to assigned environments
```

- Local user database (bcrypt passwords)
- Assign users to environments with specific role
- Admin-only: user create/edit/delete, environment management, audit log access
- Session: JWT, 8h default expiry, refresh on activity
- First-run wizard creates initial admin account

### 12. Audit Log

- Every mutation (create/update/delete/exec/logs access) logged with:
  - timestamp, user, environment, resource type, resource id, action, result
- Filterable by user, date range, action type
- Exportable as CSV
- Retention: configurable (default 90 days), auto-prune

### 13. Dashboard

- Per-environment summary: container counts by status, image count, volume count,
  network count, swarm node count (if swarm)
- Recent events (Docker event stream)
- Quick actions: start/stop/restart most-recently-used containers
- Resource usage summary (aggregate CPU%, memory across running containers)

---

## Routes (Rails conventions)

Session scoped via `Current.environment` (ApplicationController concern).

```
# Auth
GET  /login           sessions#new
POST /login           sessions#create
DEL  /logout          sessions#destroy

# Dashboard
GET  /                dashboard#index

# Environments
resources :environments

# Containers
resources :environments do
  resources :containers, only: [:index, :show, :create, :destroy] do
    member do
      post :start, :stop, :restart, :kill, :pause, :unpause, :rename
      get  :logs     # Turbo Stream
      get  :stats    # Turbo Stream / ActionCable
      get  :exec     # ActionCable terminal
    end
  end
  resources :images,   only: [:index, :show, :destroy] do
    collection { post :pull; post :prune }
    member     { post :tag }
  end
  resources :volumes,  only: [:index, :show, :create, :destroy] do
    collection { post :prune }
  end
  resources :networks, only: [:index, :show, :create, :destroy] do
    collection { post :prune }
    member     { post :connect; post :disconnect }
  end
  resources :stacks do
    member { get :file }
  end
  namespace :swarm do
    resources :services do
      member { post :rollback; get :logs }
    end
    resources :nodes,   only: [:index, :show, :update, :destroy]
    resources :configs, only: [:index, :show, :create, :destroy]
    resources :secrets, only: [:index, :show, :create, :destroy]
  end
end

# Users (admin only)
resources :users

# Audit
resources :audit_logs, only: [:index] do
  collection { get :export }
end
```

---

## Models (ActiveRecord / SQLite)

```ruby
# User
# role: admin | operator | readonly
# has_secure_password

# Environment
# endpoint_type: socket | tcp | ssh
# endpoint: /var/run/docker.sock | tcp://host:2376 | ssh://user@host

# EnvironmentAccess (join — user ↔ environment)
# role: operator | readonly  (admin implícito em todos)

# Registry
# password encrypted via Rails credentials

# AuditLog (paper_trail + custom)
# resource_type, resource_id, action, result, detail, user, environment
```

---

## Directory Layout

```
redhusk-orchestration/
├── platform-rails/               ← Rails 8 app (tudo aqui)
│   ├── app/
│   │   ├── controllers/
│   │   │   ├── application_controller.rb
│   │   │   ├── sessions_controller.rb
│   │   │   ├── dashboard_controller.rb
│   │   │   ├── environments_controller.rb
│   │   │   ├── containers_controller.rb
│   │   │   ├── images_controller.rb
│   │   │   ├── volumes_controller.rb
│   │   │   ├── networks_controller.rb
│   │   │   ├── stacks_controller.rb
│   │   │   ├── swarm/
│   │   │   └── users_controller.rb
│   │   ├── models/
│   │   │   ├── user.rb
│   │   │   ├── environment.rb
│   │   │   ├── environment_access.rb
│   │   │   ├── registry.rb
│   │   │   └── audit_log.rb
│   │   ├── services/
│   │   │   └── docker/
│   │   │       ├── client.rb        ← docker-api wrapper por environment
│   │   │       ├── container_service.rb
│   │   │       ├── image_service.rb
│   │   │       ├── swarm_service.rb
│   │   │       └── stack_service.rb
│   │   ├── channels/
│   │   │   ├── container_logs_channel.rb
│   │   │   └── container_stats_channel.rb
│   │   ├── policies/               ← Pundit
│   │   ├── components/             ← ViewComponent
│   │   └── views/
│   ├── Dockerfile
│   ├── Gemfile
│   └── VERSION
├── deploy/
│   ├── orchestration.stack.yml
│   ├── deploy-dev.sh
│   ├── .env.dev.example
│   └── .gitignore
├── .gitlab-ci.yml
├── .gitignore
└── SPEC.md
```

---

## MVP Deliverables (v0.1)

Priority order:

1. Auth (login, JWT, first-run admin setup)
2. Environment management (add local socket, TCP+TLS)
3. Container full lifecycle + logs + stats + exec
4. Images (list, pull, remove, prune)
5. Volumes (list, create, remove)
6. Networks (list, create, remove)
7. Dashboard (counts + recent events)
8. Swarm: services + nodes + stacks
9. RBAC (users, environment access)
10. Audit log

---

## Configuração (env vars — Rails)

| Variável | Descrição |
|---|---|
| `SECRET_KEY_BASE` | Rails secret (gerado com `rails secret`) |
| `DATABASE_PATH` | Path do SQLite (`/data/orchestration_<tier>.db`) |
| `RAILS_ALLOWED_HOSTS` | Host Traefik do tier |
| `APP_HOST` | Mesmo que RAILS_ALLOWED_HOSTS |

---

## Ambientes e deploy

**Deploy manual** — sem CI/CD runner (runner estava degradando a VPS).
Mesmo padrão do HuskyOS: build local + `docker stack deploy`.

| Tier | Branch | Host | Script |
|---|---|---|---|
| dev  | `develop` | orchestration-dev.redhusky.com.br | `deploy/deploy-dev.sh` |
| hml  | `hml`     | orchestration-hml.redhusky.com.br | manual (ver abaixo) |
| prod | `main`    | orchestration.redhusky.com.br     | manual (ver abaixo) |

```bash
# Dev
echo "0.1.1" > platform-rails/VERSION
bash deploy/deploy-dev.sh

# Hml/Prod (sem registry — build local no servidor)
VERSION=$(cat platform-rails/VERSION)
IMAGE="orchestration:v${VERSION}"
docker build -t "$IMAGE" platform-rails/
STACK_NAME=orchestration-prod APP_HOST=orchestration.redhusky.com.br \
  DATABASE_PATH=/data/orchestration_prod.db \
  SECRET_KEY_BASE=<secret> IMAGE="$IMAGE" \
  docker stack deploy -c deploy/orchestration.stack.yml --with-registry-auth orchestration-prod
```
