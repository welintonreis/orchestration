# Spec — Terminal ttyd (Portainer-style)

**Status:** implementado — v0.7.0  
**Versão alvo:** v0.6.0

> Implementado: ttyd 1.7.7 no Dockerfile, `TtydManager` (singleton, portas
> 7681-7730), `ContainersController#ttyd_ws` (Rack hijack + proxy bidirecional),
> rota `containers/:id/ttyd-ws`, `terminal_controller.js` reescrito p/ WebSocket
> direto. Correção vs spec: protocolo ttyd real prefixa comando em **ambas**
> direções (output = frame com 1º byte `0`, não binário cru) e exige mensagem
> inicial `JSON_DATA` `{AuthToken,columns,rows}` + subprotocolo `tty` — o JS
> implementa isso. Proxy continua transparente. `TerminalChannel` mantido (compat).

---

## Problema com terminal atual

| Problema | Causa raiz |
|---|---|
| Lag ~100ms por tecla | `ActionCable.server.broadcast` → Solid Cable (SQLite polling a cada 100ms) |
| Tab completion inconsistente | bash nem sempre disponível, não é bug do Rails |
| TUI apps (nano, vim) quebram | dimensões PTY enviadas só no `connected` callback, antes do resize inicial |
| "command not found" não aparece | broadcast perdido no delay |

---

## Solução proposta

Substituir o transporte ActionCable + Solid Cable por:

1. **ttyd** (processo C) rodando dentro do container da orquestração — já tem `docker` CLI
2. **Rack WebSocket proxy** no Rails — recebe WS do browser, repassa bytes crus para ttyd
3. **Frontend direto** — xterm.js conecta ao proxy WS sem ActionCable

Fluxo:
```
Browser (xterm.js)
  ↕ WSS /containers/:id/ttyd-ws  (HTTPS via Traefik)
Rails (ContainersController#ttyd_ws)  — Rack hijack
  ↕ WS ws://127.0.0.1:PORT/ws  (loopback, sem TLS)
ttyd process  — porta efêmera 7681-7730
  ↕ PTY
docker exec -it CONTAINER_ID /bin/sh
```

Latência esperada: <5ms (sem SQLite, sem threads intermediários para broadcast).

---

## Protocolo ttyd (v1.7.x)

| Direção | Tipo frame WS | Formato |
|---|---|---|
| Client → Server (input) | text | `"0" + keystroke_bytes` |
| Client → Server (resize) | text | `"1{"columns":N,"rows":M}"` |
| Server → Client (output) | binary | bytes crus do PTY |

O proxy Rails é **transparente** — repassa frames sem parsear, então o protocolo não afeta o código Ruby.

---

## Implementação

### 1. Dockerfile — instalar ttyd

```dockerfile
RUN ARCH=$(dpkg --print-architecture) && \
    case "$ARCH" in \
      amd64) TARCH=x86_64 ;; \
      arm64) TARCH=aarch64 ;; \
      *) echo "unsupported: $ARCH" && exit 1 ;; \
    esac && \
    curl -fsSL "https://github.com/tsl0922/ttyd/releases/download/1.7.7/ttyd.${TARCH}" \
         -o /usr/local/bin/ttyd && \
    chmod +x /usr/local/bin/ttyd
```

### 2. TtydManager — `app/services/ttyd_manager.rb`

Singleton. Responsabilidades:
- Spawnar `ttyd --interface 127.0.0.1 --port PORT --once --writable -- docker exec -it ID sh`
- Rastrear porta ocupada por container_id → liberar após `--once`
- `get_or_spawn(container_id)` → porta
- `cleanup(container_id)` → mata processo, libera porta

Range de portas: 7681-7730 (50 sessões simultâneas).

### 3. ContainersController — `#ttyd_ws`

```ruby
def ttyd_ws
  return head :bad_request unless request.env["HTTP_UPGRADE"]&.downcase == "websocket"

  port      = TtydManager.instance.get_or_spawn(params[:id])
  env       = request.env
  env["rack.hijack"].call
  browser   = env["rack.hijack_io"]
  ttyd_sock = TCPSocket.new("127.0.0.1", port)

  # Repassa upgrade handshake para ttyd, devolve 101 para browser
  forward_ws_handshake(browser, ttyd_sock, env)

  # Proxy bidirecional de bytes crus
  t1 = Thread.new { IO.copy_stream(ttyd_sock, browser) rescue nil }
  t2 = Thread.new { IO.copy_stream(browser, ttyd_sock) rescue nil }
  t1.join; t2.join
ensure
  browser&.close rescue nil
  ttyd_sock&.close rescue nil
  TtydManager.instance.cleanup(params[:id]) rescue nil
end
```

`before_action :require_authentication` cobre a rota — auth antes do hijack.

### 4. Routes

```ruby
get "containers/:id/ttyd-ws", to: "containers#ttyd_ws", as: :container_ttyd_ws
```

### 5. terminal_controller.js — trocar ActionCable por WebSocket direto

```javascript
#setupWebSocket() {
  const proto = location.protocol === "https:" ? "wss:" : "ws:"
  this.ws = new WebSocket(`${proto}//${location.host}/containers/${this.containerIdValue}/ttyd-ws`)
  this.ws.binaryType = "arraybuffer"

  this.ws.onopen = () => {
    this.term.write("\x1b[1;32m● Connected\x1b[0m\r\n")
    this.#sendResize()
  }
  this.ws.onmessage = (e) => {
    this.term.write(e.data instanceof ArrayBuffer ? new Uint8Array(e.data) : e.data)
  }
  this.ws.onclose = () => this.term.write("\r\n\x1b[31m[disconnected]\x1b[0m\r\n")
}

// Input: protocolo ttyd — prefixo "0"
this.term.onData(data => this.ws?.readyState === 1 && this.ws.send("0" + data))

// Resize: protocolo ttyd — prefixo "1" + JSON
#sendResize() {
  if (this.ws?.readyState === 1)
    this.ws.send(`1${JSON.stringify({ columns: this.term.cols, rows: this.term.rows })}`)
}
```

---

## Riscos e mitigações

| Risco | Impacto | Mitigação |
|---|---|---|
| Cada terminal trava 1 thread Puma | Com 5+ sessões simultâneas, requests lentos | Aumentar `WEB_CONCURRENCY` no stack yml (default Puma: 16 threads) |
| ttyd `--once` → processo morto após desconexão | Reconexão não funciona automaticamente | `get_or_spawn` detecta processo morto, spawna novo |
| Rack hijack incompatível com Thruster | WS proxy não funciona | Thruster passa HTTP/1.1 Upgrade direto para Puma — testado e compatível |
| Range de portas esgotado (50 sessões) | Erro ao abrir terminal | Aumentar range ou adicionar fila de espera |
| Processo ttyd órfão (Rails crasha) | Porta ocupada, `docker exec` pendente | `--once` + OS mata processos filhos na morte do pai (pgroup) |
| `docker exec` em container parado | ttyd inicia, conecta, shell falha imediatamente | ttyd fecha conexão → xterm mostra `[disconnected]` |
| Protocolo ttyd muda em versão futura | Frames não interpretados corretamente | Proxy é transparente — protocolo só importa para JS client, fácil ajustar |
| Autenticação: proxy não verifica token por sessão | N/A | `before_action :require_authentication` bloqueia antes do hijack |
| Thruster bufferiza response antes de enviar | Handshake WS atrasado ou quebrado | Thruster não bufferiza streams/upgrades — pass-through direto |

---

## O que NÃO muda

- View `terminal.html.erb` — header, root toggle, user input: tudo igual
- `TerminalChannel` — mantido para compatibilidade (pode ser removido depois)
- xterm.js versão e tema

---

## Fix imediato (sem ttyd) — alternativa rápida

Trocar `ActionCable.server.broadcast` por `transmit` direto em `TerminalChannel`:

```ruby
# Antes (passa por Solid Cable, ~100ms lag):
ActionCable.server.broadcast(@channel_name, { output: chunk })

# Depois (direto para WebSocket da conexão, ~1ms):
transmit({ output: chunk })
```

Essa mudança isolada elimina o lag sem precisar de ttyd. Pode ser feita agora como fix interim enquanto o ttyd fica para v0.6.0.

---

## Ordem de implementação sugerida

1. **Agora (fix rápido):** `ActionCable.server.broadcast` → `transmit` em `TerminalChannel` — elimina lag, 5min
2. **v0.6.0 (ttyd completo):** Dockerfile + TtydManager + proxy action + terminal_controller.js rewrite
