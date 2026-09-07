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

// Muted ANSI palette: no near-white text, and diff-style red/green (deletions/
// insertions from git/diff tools) desaturated instead of pure alert colors.
const DARK_THEME = {
  background: "#0d1117", foreground: "#c9d1d9", cursor: "#58a6ff", cursorAccent: "#0d1117",
  selectionBackground: "rgba(88,166,255,0.3)",
  black: "#484f58", red: "#c9706a", green: "#7a9d76", yellow: "#d29922",
  blue: "#58a6ff", magenta: "#a98cd0", cyan: "#4fa8b0", white: "#9099a3",
  brightBlack: "#6e7681", brightRed: "#d99089", brightGreen: "#93b98f",
  brightYellow: "#e3b341", brightBlue: "#79c0ff", brightMagenta: "#c3aede",
  brightCyan: "#7fc9cf", brightWhite: "#c9d1d9",
}
const LIGHT_THEME = {
  background: "#e5e7eb", foreground: "#374151", cursor: "#374151", cursorAccent: "#e5e7eb",
  selectionBackground: "rgba(55,65,81,0.2)",
  black: "#24292f", red: "#a8534a", green: "#4b7a5c", yellow: "#6b4d00",
  blue: "#0969da", magenta: "#8250df", cyan: "#1b7c83", white: "#6e7781",
  brightBlack: "#57606a", brightRed: "#b96a5e", brightGreen: "#5c8f6e",
  brightYellow: "#7d5c1c", brightBlue: "#218bff", brightMagenta: "#a475f9",
  brightCyan: "#3f97a0", brightWhite: "#8c959f",
}

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
      theme: document.documentElement.classList.contains("dark") ? DARK_THEME : LIGHT_THEME,
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

    this.resizeObserver = new ResizeObserver(() => this.#scheduleFit())
    this.resizeObserver.observe(this.containerTarget)
    this._onActivated = () => {
      this.#scheduleFit()
      requestAnimationFrame(() => this.term?.focus())
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
    clearTimeout(this._fitTimer)
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

  // Every fit that changes the column count makes xterm reflow the whole
  // scrollback (10k lines) AND sends window-change to tmux, which answers with
  // a full-screen repaint. During a width animation or a drag the observer
  // fires per frame, so we paid that a dozen times — and each reflow delayed
  // the next frame, producing yet another intermediate width. Opening the
  // files split cost ~940ms of blocked main thread this way (closing ~640ms:
  // widening is the cheaper direction, which is why only opening felt bad).
  // Trailing-only: fit once, after the width stops moving.
  #scheduleFit() {
    clearTimeout(this._fitTimer)
    this._fitTimer = setTimeout(() => this.#fitIfVisible(), 60)
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
