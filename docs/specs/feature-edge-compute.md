# Spec: Edge Compute Avançado (agents multi-host)

> Criado: 2026-07-02 | Status: draft | Autor: Claude/Welinton
> Substitui o stub atual de Settings→Edge (edge_key/edge_enabled em AppSetting)

## Objetivo

Gerenciar hosts Docker/Podman remotos (VPS, boxes atrás de NAT, edge devices)
sem expor daemon na rede: agente outbound-only com túnel reverso, deploy de
stacks em frota, terminal/logs remotos e rollout escalonado.

## Contexto

Hoje "multi-host" = Environment `tcp://` — HTTP puro contra o daemon (sem TLS,
inaceitável fora de rede confiável) e não atravessa NAT. Os concorrentes
resolveram com agents: Portainer Edge (poll + túnel sob demanda), Komodo
Periphery (agent permanente por host). O modelo agent é estritamente superior:
o host remoto só faz **conexões de saída** para o painel (443), nada de portas
abertas, nada de mTLS de daemon para distribuir.

O stub existente (`Settings::EdgeController`: `edge_key`, `edge_enabled`,
`edge_polling_interval`) vira a base de configuração real.

Alternativa descartada: mTLS direto no daemon remoto (2376) — não passa NAT,
gestão de CA manual, superfície do daemon exposta. Descartado wireguard mesh —
ótimo, mas exige mexer em rede do host; agent em container é `docker run` e fim.

## Interface

### Entrada
- **Enrollment**: tela Edge gera comando one-liner por node:
  `docker run -d --restart=always -v /var/run/docker.sock:/var/run/docker.sock \
   -e EDGE_URL=https://orchestration.redhusky.com.br -e EDGE_TOKEN=<jwt-de-enrollment> \
   redhusk/orchestration-agent:vX.Y.Z`
  Token de enrollment = JWT curto (15min, single-use, assinado com `edge_key`)
  contendo nome/grupo do node. Agent troca por token permanente por-node no
  primeiro contato (`POST /api/edge/enroll`).
- **Agent** (novo componente, MESMO repo, `agent/` — Go ou Ruby? ver Decisões):
  1. WebSocket persistente `wss://…/api/edge/tunnel` (Action Cable NÃO —
     canal raw tipo o ttyd proxy, multiplexado).
  2. Fallback polling HTTP (`edge_polling_interval`, default 30s) quando WS
     não estabelece (proxies corporativos).
- **Fleet UI**: Environments ganham tipo `edge` (endpoint = agent id);
  aparecem no seletor como hoje. Grupos de environments = grupos edge.
  Tela `edge/nodes`: status (online/última vez visto), versão do agent,
  SO/arch, métricas resumidas.

### Saída
- **Transparência total nas telas existentes**: containers/images/volumes/
  logs/terminal/stacks funcionam num node edge — `DockerClient` fala com o
  daemon remoto **através do túnel** (proxy local por node, ver Implementação).
- **Deploy em frota**: `GitStack` ganha `target_group_id` — deploy aplica em
  todos os nodes do grupo, **escalonado** (1 node → espera health → resto em
  lotes de N, aborta no 1º lote falho). Resultado por node na tela da stack.
- **Comandos offline-tolerantes**: fila por node (tabela `edge_commands`),
  agent puxa/confirma; node offline executa ao voltar (TTL configurável,
  default 24h, depois expira com alerta).
- **Métricas/heartbeat**: agent manda a cada intervalo: cpu/ram/disk/containers
  running — alimenta `HostMetric` com `node_id` e os alertas existentes.
- **Terminal remoto**: browser → painel (WS, rota ttyd atual) → túnel do agent
  → `docker exec` no host remoto. Reusa TtydManager no LADO DO AGENT
  (mesmo protocolo, já depurado — ver postmortem stderr!).

### Restrições não-funcionais
- Segurança: token por-node revogável (tela de nodes → revoke), JWT assinado
  com `edge_key` rotacionável (`regenerate_key` existente invalida frota →
  confirmar com dialog); todo tráfego TLS via Traefik; agent NUNCA abre porta.
- Latência terminal via túnel: alvo <100ms echo em WAN (aceitável; medir com
  o probe do postmortem).
- Escala alvo: 50 nodes, 1 conexão WS cada — Puma single-worker não segura
  (1 thread/WS) → túneis terminam num processo dedicado
  (`bin/edge-hub`, Rack standalone no mesmo container, porta interna) OU
  AnyCable; decidir no primeiro benchmark. Polling não tem esse problema.
- Banco: SQLite aguenta 50 nodes × heartbeat 30s; revisar índices
  (`edge_commands(node_id, status)`).

### Restrições de compatibilidade
- Agent multi-arch: amd64 + arm64 (edge devices).
- Runtime no edge: Docker ou Podman (reusa detecção da spec podman).
- k8s no edge (k3s em box remota): o túnel transporta também a API 6443 —
  Environment kubernetes com `via_edge_node_id` (liga as três specs).

## Implementação

### Arquivos a criar/modificar
- `agent/` — novo binário. **Go** (single static binary, cross-compile amd64/
  arm64 trivial, footprint ~10MB): conecta WS, multiplexa streams (yamux),
  proxy local → docker.sock, executor de comandos da fila, coletor de métricas.
- `app/controllers/api/edge_controller.rb` — enroll, poll, push de métricas,
  ack de comandos (JSON, auth por token de node — `authenticate_or_request_with_http_token`).
- `app/controllers/api/edge_tunnels_controller.rb` — WS raw (rack hijack, mesmo
  padrão do ttyd_ws) registrando túnel no `EdgeTunnelRegistry` (singleton,
  token→socket).
- `app/services/edge_tunnel_registry.rb` — mapa node→conexão; `DockerClient`
  com endpoint `edge://<node-id>` roteia por aqui (Excon middleware custom OU
  proxy TCP local efêmero por node — começar pelo proxy local: zero mudança
  no DockerClient).
- `app/models/edge_node.rb`, `edge_command.rb` + migrations.
- `app/jobs/edge_fleet_deploy_job.rb` — rollout escalonado.
- `deploy/orchestration.stack.yml` — sem mudança (agent é imagem separada
  `redhusk/orchestration-agent:vX.Y.Z`, build no mesmo repo).
- Settings→Edge — vira dashboard de enrollment + lista de nodes.

### Decisões técnicas
- **Go no agent, Rails no hub**: agent precisa ser um binário estático que
  roda em qualquer box sem runtime; o resto do cérebro fica no Rails.
- **yamux sobre 1 WS** (não 1 WS por stream): terminal + API + logs
  simultâneos num socket; reconexão única.
- **Proxy TCP local efêmero por node** no primeiro release: quando uma tela
  pede um node edge, o hub abre `127.0.0.1:PORT` que encaminha pelo túnel;
  `DockerClient.new(endpoint: "tcp://127.0.0.1:PORT")` funciona **sem tocar
  em nenhuma tela**. Otimizar depois se necessário.
- **Fila de comandos no banco** (não só túnel): é o que dá tolerância a
  offline — diferencial do modelo Portainer Edge async.

### Anti-patterns a evitar
- NÃO usar Action Cable para o túnel (Solid Cable = SQLite polling; a lição
  de latência do terminal já foi aprendida uma vez).
- NÃO aceitar enrollment com o `edge_key` cru (só JWT curto derivado).
- NÃO deixar o agent logar payloads (pode conter env/secrets de stacks).
- NÃO fazer o hub confiar no node_id declarado — sempre do token.

## Testes

- [ ] Enroll de node local (agent apontando pro próprio painel) → aparece online
- [ ] Containers/logs/terminal do node edge nas telas existentes
- [ ] Probe de terminal via túnel: echo <100ms
- [ ] Node offline: comando enfileirado → volta → executa → ack
- [ ] Revoke de token derruba túnel e recusa reconexão
- [ ] Rollout em grupo de 3 nodes com 1 falhando → aborta lote, alerta
- [ ] Deploy testado em staging

## Rollout

Fases: (1) enroll + heartbeat + métricas; (2) túnel + telas transparentes;
(3) fila offline + fleet deploy; (4) k3s-via-edge. Cada fase deployável.
Stub atual de Settings→Edge migra sem breaking (mesmas AppSettings).
Feature flag: `edge_enabled` já existe.
