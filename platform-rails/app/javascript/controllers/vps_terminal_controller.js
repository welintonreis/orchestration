import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"
import { Terminal } from "@xterm/xterm"
import { FitAddon } from "@xterm/addon-fit"
import { WebLinksAddon } from "@xterm/addon-web-links"
import { ClipboardAddon } from "@xterm/addon-clipboard"
import { SerializeAddon } from "@xterm/addon-serialize"

// One shared cable connection per tab — same pattern as consumer.js used by
// stats_controller, avoids opening a new WebSocket per terminal pane.
let sharedConsumer = null
const consumer = () => (sharedConsumer ||= createConsumer())

// Real SSH terminal to a VpsHost — ported from redhusky-remote-ssh's
// terminal_controller.js (ActionCable + `transmit`, not ttyd/broadcast, see
// SPEC-TERMINAL-TTYD.md).
export default class extends Controller {
  static targets = ["container", "status"]
  static values  = { sessionToken: String, sessionId: String, hostId: String }

  connect() {
    this.term = new Terminal({
      fontFamily: '"JetBrainsMono Nerd Font","JetBrains Mono","Fira Code",Menlo,Monaco,Consolas,monospace',
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

    this.fitAddon = new FitAddon()
    this.serializeAddon = new SerializeAddon()
    this.term.loadAddon(this.fitAddon)
    this.term.loadAddon(new WebLinksAddon())
    this.term.loadAddon(new ClipboardAddon())
    this.term.loadAddon(this.serializeAddon)

    this.term.open(this.containerTarget)
    this.containerTarget.addEventListener("click", () => this.term.focus())
    this.#fitIfVisible()
    this.term.focus()

    this._sshDisconnected = false
    this._savedBuffer = null

    this.term.onData((data) => {
      if (this._sshDisconnected) { this._sshDisconnected = false; this.doReconnect(); return }
      this.subscription?.send({ input: data })
    })
    this.term.onResize(({ cols, rows }) => this.subscription?.send({ action: "resize", cols, rows }))

    this.resizeObserver = new ResizeObserver(() => this.#fitIfVisible())
    this.resizeObserver.observe(this.containerTarget)
    this._onActivated = () => {
      requestAnimationFrame(() => {
        this.#fitIfVisible()
        this.term?.focus()
      })
    }
    this.element.addEventListener("terminal:activated", this._onActivated)
    this.#setupCopyPaste()
    this.#setupActionCable()

    // Ensure layout fits after initial mount
    requestAnimationFrame(() => this.#fitIfVisible())
    setTimeout(() => this.#fitIfVisible(), 100)

    if (document.fonts?.ready) {
      document.fonts.ready.then(() => { this.#fitIfVisible(); this.term?.refresh(0, (this.term.rows || 1) - 1) })
    }
  }

  disconnect() {
    this.element.removeEventListener("terminal:activated", this._onActivated)
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
          this.#fitIfVisible()
          this.term.focus()
          this.subscription.send({ action: "resize", cols: this.term.cols, rows: this.term.rows })
          if (this._savedBuffer) {
            this.term.write(this._savedBuffer)
            this.term.writeln("\r\n\x1b[2m--- reconectado ---\x1b[0m\r\n")
            this._savedBuffer = null
          }
          this.term.write("\x1b[?1000l\x1b[?1002l\x1b[?1003l\x1b[?1005l\x1b[?1006l\x1b[?1015l")
        },
        disconnected: () => this.#setStatus("disconnected"),
        rejected: () => this.#setStatus("error", "Conexão rejeitada"),
        received: (data) => {
          if (data.output) this.term.write(Uint8Array.from(atob(data.output), c => c.charCodeAt(0)))
          if (data.status) {
            this.#setStatus(data.status, data.message)
            if (data.status === "disconnected") {
              this._savedBuffer = this.serializeAddon.serialize()
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
    try {
      this.fitAddon.fit()
    } catch {}
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

    // Auto-copy when a left-button drag finishes with text selected — copies
    // inside the user gesture instead of waiting for a right-click later,
    // which can race xterm's own SelectionService clearing on the next mousedown.
    this.containerTarget.addEventListener("mouseup", (e) => {
      if (e.button !== 0) return
      const sel = this.term.getSelection()
      if (sel) this.#writeClipboard(sel)
    })

    this.containerTarget.addEventListener("contextmenu", (e) => {
      e.preventDefault(); e.stopPropagation()
      if (this.term.hasSelection()) { this.#writeClipboard(this.term.getSelection()); this.term.clearSelection() }
      else navigator.clipboard.readText().then(t => this.subscription?.send({ input: t })).catch(() => {})
      this.term.focus()
    }, true)
  }

  // execCommand("copy") runs synchronously inside the user gesture and needs no
  // secure context — try it first. Chrome silently no-ops it in some contexts,
  // so fall back to the async Clipboard API rather than fail silently.
  #writeClipboard(text) {
    if (!text) return Promise.resolve(false)
    if (this.#execCopy(text)) return Promise.resolve(true)
    if (navigator.clipboard && window.isSecureContext) {
      return navigator.clipboard.writeText(text).then(() => true).catch(() => false)
    }
    return Promise.resolve(false)
  }

  #execCopy(text) {
    try {
      const ta = document.createElement("textarea")
      ta.value = text
      ta.setAttribute("readonly", "")
      ta.style.position = "fixed"
      ta.style.top = "-9999px"
      document.body.appendChild(ta)
      const active = document.activeElement
      ta.select()
      const ok = document.execCommand("copy")
      document.body.removeChild(ta)
      if (active && active.focus) active.focus()
      return ok
    } catch {
      return false
    }
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
