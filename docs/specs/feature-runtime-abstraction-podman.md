# Spec: Runtime Abstraction + Podman

> Criado: 2026-07-02 | Status: draft | Autor: Claude/Welinton

## Objetivo

Rodar o painel contra Podman (rootful ou rootless) além do Docker, com a UI
degradando graciosamente onde o runtime não tem a capability (ex.: Swarm).

## Contexto

Podman 4/5 expõe uma **API compatível com Docker** (`/v1.40+` compat) no socket
(`/run/podman/podman.sock` rootful, `$XDG_RUNTIME_DIR/podman/podman.sock`
rootless) — ~90% do `DockerClient` atual funciona sem mudança. O que quebra:

1. **Paths hardcoded `/v1.47`** — Podman compat aceita, mas versões antigas não;
   daemons Docker velhos também não. Negociar versão.
2. **Endpoints Swarm** (`/services`, `/nodes`, `/secrets`, `/configs`,
   `/tasks`, `/swarm`) — Podman responde 404/erro. Hoje várias telas assumem
   swarm e mostram erro cru.
3. **Terminal**: `TtydManager` chama `docker exec` CLI. CLI `docker` funciona
   contra socket Podman via `-H`, mas o correto é detectar e usar `podman
   --url` quando disponível.
4. **Compose**: `docker compose` (plugin) funciona com `DOCKER_HOST` apontando
   pro socket Podman; `GitDeployer` modo `compose` funciona; modo `swarm_stack`
   não existe em Podman → esconder opção.

Alternativa descartada: cliente libpod nativo (`/v5.x/libpod/...`) — dobra a
superfície de código para ganhar features que o painel não usa (pods, quadlets)
— fica para fase 2 se houver demanda.

## Interface

### Entrada
- `Environment` ganha `runtime` (string: `docker` | `podman`, default
  `docker`) — **detectado automaticamente** no primeiro contato e cacheado:
  `GET /_ping` → headers (`Libpod-Api-Version` presente = podman) ou
  `GET /version` → `Components[].Name == "Podman Engine"`.
- Nenhuma mudança de fluxo para o usuário: cadastra endpoint unix/tcp como hoje.

### Saída
- `DockerClient#capabilities` → `{ swarm:, compose:, pods: }` calculado por
  runtime + `LocalNodeState`.
- Navegação/telas Swarm (services, nodes, stacks swarm, configs, secrets,
  topology) escondidas quando `capabilities.swarm == false` (hoje: erro).
- Badge do runtime no seletor de environment (ícone docker/podman).

### Restrições não-funcionais
- Detecção: 1 chamada extra por environment, cacheada em `Rails.cache` 10min.
- Zero regressão em Docker: suite atual (141 runs) verde.
- Rootless Podman: socket do usuário — documentar bind-mount no stack yml.

## Implementação

### Arquivos a criar/modificar
- `app/services/docker_client.rb` — (a) negociar `API_VERSION` uma vez via
  `/_ping` (header `Api-Version`), guardar em ivar, prefixar paths com ela;
  (b) método `runtime` (`:docker`/`:podman`) + `capabilities`; (c) swarm
  endpoints levantam `UnsupportedError` claro quando `!capabilities[:swarm]`.
- `app/models/environment.rb` — coluna `runtime` (migration), preenchida na
  detecção; `ENDPOINT_TYPES` inalterado.
- `app/controllers/application_controller.rb` — helper `runtime_capabilities`
  para as views (menu condicional).
- `app/views/layouts/_sidebar*` — itens swarm condicionais.
- `app/services/ttyd_manager.rb` — `container_cli(endpoint, runtime)`:
  `["podman", "--url", endpoint]` quando podman e binário presente, senão
  `["docker", "-H", endpoint]` (compat). Dockerfile: instalar `podman-remote`.
- `app/services/git_deployer.rb` — esconder/recusar `swarm_stack` quando
  runtime podman (validação no model `GitStack`).

### Decisões técnicas
- **Compat API, não libpod**: menor diff, mesma superfície de testes.
- **Detecção por header, não por config manual**: um campo a menos para o
  usuário errar; override manual só se a detecção falhar (campo `runtime`
  editável no form de Environment).
- **`UnsupportedError` tipado** em vez de `rescue` genérico: as telas mostram
  "não suportado neste runtime" em vez de "erro".

### Anti-patterns a evitar
- NÃO duplicar `PodmanClient` — é o mesmo protocolo; um if de capability basta.
- NÃO chamar `/_ping` a cada request (cache).
- NÃO assumir que tcp:// podman tem TLS — mesma pendência do Docker remoto
  (ver `feature-edge-compute.md` para a resposta certa a hosts remotos).

## Testes

- [ ] Happy path: environment unix:// Docker continua 100% (suite atual verde)
- [ ] Podman rootful local: containers/images/volumes/networks/logs/terminal OK
- [ ] Telas swarm escondidas em environment podman; deep-link → mensagem clara
- [ ] Edge case: daemon Docker < 1.47 → version negotiation usa a do daemon
- [ ] Edge case: `/_ping` timeout → assume docker, loga warning, não trava tela
- [ ] Deploy testado em staging (stack dev)

## Rollout

Migration aditiva (`runtime` nullable, backfill lazy na detecção). Sem feature
flag — comportamento Docker é o fallback em qualquer dúvida. Reversível por
revert simples.
