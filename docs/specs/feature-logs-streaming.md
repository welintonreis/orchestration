# Spec — Logs de container em tempo real (Fase 14)

**Status:** ✅ implementado — `LogsChannel` (ActionCable) + `log_stream_controller.js`, já shippado antes desta verificação.

## Gatilhos

1. Debug de produção onde o refresh manual da página de logs atrapalhar
   de verdade (hoje: logs estáticos + refresh).

## Desenho

- **Não usar ActionCable/Solid Cable** pro stream — lição do terminal
  (SPEC-TERMINAL-TTYD): polling de 100ms do Solid Cable adiciona lag e
  perde chunks. Mesmo padrão do ttyd: **Rack hijack + SSE** (logs são
  unidirecionais — SSE basta, WebSocket é overkill).
- `GET /containers/:id/logs/stream` (SSE): DockerClient já demuxa o
  stream 8-byte do daemon (`follow=1&tail=200&timestamps=1`); cada chunk
  vira `data:` event. Heartbeat comment a cada 15s (Traefik idle timeout).
- Front: `EventSource` + append num `<pre>` com autoscroll travável
  (checkbox "seguir"), filtro client-side por substring, botão download
  (rota existente não-follow).
- Reconexão: EventSource reconecta sozinho; `Last-Event-ID` = timestamp
  do último log → `since=` no daemon, sem duplicar linhas.
- Serviços Swarm (multi-task): fase 1 = logs do service via
  `/services/:id/logs` (daemon agrega); por-task depois se precisar.

## Custo

1 sessão (a demux já existe; é rota SSE + JS).
