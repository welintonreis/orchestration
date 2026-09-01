import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"
import { Terminal } from "@xterm/xterm"
import { FitAddon } from "@xterm/addon-fit"
import { WebLinksAddon } from "@xterm/addon-web-links"
import { ClipboardAddon } from "@xterm/addon-clipboard"

// One shared cable connection per tab — same pattern as consumer.js used by
// stats_controller, avoids opening a new WebSocket per terminal pane.
let sharedConsumer = null
const consumer = () => (sharedConsumer ||= createConsumer())

// Real SSH terminal to a VpsHost — ported from redhusky-remote-ssh's
// terminal_controller.js (ActionCable + `transmit`, not ttyd/broadcast, see
// SPEC-TERMINAL-TTYD.md). Chrome trimmed to what this port needs: no color
// scheme picker / search panel / settings drawer.
// ponytail: add those back only if asked — core parity (low-latency shell,
// resize, reconnect) is what "igualzinho" actually requires.
export default class extends Controller {
  static targets = ["container", "status"]
  static values  = { sessionToken: String, sessionId: String, hostId: String }

  connect() {
    this.term = new Terminal({
      fontFamily: '"JetBrains Mono","Fira Code",Menlo,Monaco,Consolas,monospace',
      fontSize: 13,
      lineHeight: 1.25,
      scrollback: 10000,
      cursorBlink: true,
      allowProposedApi: true,
      rightClickSelectsWord: false,
      theme: {
        background: "#0d1117", foreground: "#e6edf3", cursor: "#58a6ff", cursorAccent: "#0d1117",
        selectionBackground: "rgba(88,166,255,0.3)",
        black: "#484f58", red: "#ff7b72", green: "#3fb950", yellow: "#d29922",
        blue: "#58a6ff", magenta: "#bc8cff", cyan: "#39c5cf", white: "#b1bac4",
        brightBlack: "#6e7681", brightRed: "#ffa198", brightGreen: "#56d364",
        brightYellow: "#e3b341", brightBlue: "#79c0ff", brightMagenta: "#d2a8ff",
        brightCyan: "#56d4dd", brightWhite: "#f0f6fc",
      }
    })
    // NO WebglAddon: its glyph atlas leaves rows overlapping on reflow (same
    // bug documented for the container terminal) — DOM renderer is plenty.
    this.fitAddon = new FitAddon()
    this.term.loadAddon(this.fitAddon)
    this.term.loadAddon(new WebLinksAddon())
    this.term.loadAddon(new ClipboardAddon())

    this.term.open(this.containerTarget)
    this.containerTarget.addEventListener("click", () => this.term.focus())
    this.#fitIfVisible()
    this.term.focus()

    this._sshDisconnected = false

    this.term.onData((data) => {
      if (this._sshDisconnected) { this._sshDisconnected = false; this.doReconnect(); return }
      this.subscription?.send({ input: data })
    })
    this.term.onResize(({ cols, rows }) => this.subscription?.send({ action: "resize", cols, rows }))

    this.resizeObserver = new ResizeObserver(() => this.#fitIfVisible())
    this.resizeObserver.observe(this.containerTarget)
    this.#setupCopyPaste()
    this.#setupActionCable()

    if (document.fonts?.ready) {
      document.fonts.ready.then(() => { this.#fitIfVisible(); this.term?.refresh(0, (this.term.rows || 1) - 1) })
    }
  }

  disconnect() {
    this.subscription?.unsubscribe()
    this.resizeObserver?.disconnect()
    this.term?.dispose()
  }

  #setupActionCable() {
    this.subscription = consumer().subscriptions.create(
      { channel: "VpsTerminalChannel", session_token: this.sessionTokenValue, cols: this.term.cols, rows: this.term.rows },
      {
        connected: () => {
          this.#setStatus("connected")
          this.term.focus()
          this.subscription.send({ action: "resize", cols: this.term.cols, rows: this.term.rows })
        },
        disconnected: () => this.#setStatus("disconnected"),
        rejected: () => this.#setStatus("error", "Conexão rejeitada"),
        received: (data) => {
          if (data.output) this.term.write(Uint8Array.from(atob(data.output), c => c.charCodeAt(0)))
          if (data.status) {
            this.#setStatus(data.status, data.message)
            if (data.status === "disconnected") {
              this._sshDisconnected = true
              this.term.writeln("\r\n\x1b[33mDesconectado. Pressione uma tecla para reconectar…\x1b[0m")
            }
          }
        }
      }
    )
  }

  async doReconnect() {
    this.term.writeln("\r\n\x1b[33mReconectando…\x1b[0m")
    try {
      await fetch(`/vps_hosts/${this.hostIdValue}/terminal_sessions/${this.sessionIdValue}/reconnect`, {
        method: "POST",
        headers: { "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content, "Accept": "application/json" }
      })
      this.subscription?.unsubscribe()
      this.#setupActionCable()
    } catch {
      this._sshDisconnected = true
      this.term.writeln("\r\n\x1b[31mFalha ao reconectar. Pressione uma tecla para tentar de novo…\x1b[0m")
    }
  }

  #fitIfVisible() {
    if (!this.containerTarget.offsetParent) return
    try { this.fitAddon.fit() } catch {}
  }

  #setupCopyPaste() {
    this.term.attachCustomKeyEventHandler((event) => {
      if (event.type !== "keydown") return true
      if (event.ctrlKey && !event.shiftKey && event.key === "c" && this.term.hasSelection()) {
        this.#writeClipboard(this.term.getSelection()); this.term.clearSelection(); return false
      }
      if (event.ctrlKey && event.shiftKey && event.key === "C") {
        const sel = this.term.getSelection()
        if (sel) { this.#writeClipboard(sel); this.term.clearSelection() }
        return false
      }
      if (event.ctrlKey && event.shiftKey && event.key === "V") {
        navigator.clipboard.readText().then(t => this.subscription?.send({ input: t })).catch(() => {})
        return false
      }
      return true
    })

    const swallowRight = (e) => { if (e.button === 2) { e.preventDefault(); e.stopPropagation() } }
    this.containerTarget.addEventListener("mousedown", swallowRight, true)
    this.containerTarget.addEventListener("mouseup", swallowRight, true)
    this.containerTarget.addEventListener("contextmenu", (e) => {
      e.preventDefault(); e.stopPropagation()
      if (this.term.hasSelection()) { this.#writeClipboard(this.term.getSelection()); this.term.clearSelection() }
      else navigator.clipboard.readText().then(t => this.subscription?.send({ input: t })).catch(() => {})
      this.term.focus()
    }, true)
  }

  #writeClipboard(text) {
    if (!text) return
    try {
      const ta = document.createElement("textarea")
      ta.value = text; ta.setAttribute("readonly", ""); ta.style.position = "fixed"; ta.style.top = "-9999px"
      document.body.appendChild(ta); ta.select()
      document.execCommand("copy")
      document.body.removeChild(ta)
    } catch {}
  }

  #setStatus(status, message = null) {
    if (!this.hasStatusTarget) return
    const dot = this.statusTarget.querySelector("[data-status-dot]")
    const label = this.statusTarget.querySelector("[data-status-label]")
    const map = {
      connected:    { color: "bg-green-400",  text: "Conectado" },
      connecting:   { color: "bg-yellow-400", text: "Conectando…" },
      disconnected: { color: "bg-red-500",    text: "Desconectado" },
      error:        { color: "bg-red-500",    text: message || "Erro" },
    }
    const s = map[status] || map.disconnected
    if (dot) dot.className = `w-2 h-2 rounded-full shrink-0 ${s.color}`
    if (label) label.textContent = s.text
  }
}
