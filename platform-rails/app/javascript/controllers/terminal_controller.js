import { Controller } from "@hotwired/stimulus"
import { Terminal } from "@xterm/xterm"
import { FitAddon } from "@xterm/addon-fit"
import { WebLinksAddon } from "@xterm/addon-web-links"
import { ClipboardAddon } from "@xterm/addon-clipboard"

// ttyd wire protocol (command = first byte of each message).
// Client → server: INPUT "0", RESIZE "1"+JSON, initial JSON_DATA "{...}".
// Server → client: OUTPUT "0", SET_TITLE "1", SET_PREFERENCES "2".
const CMD_OUTPUT = "0"

// xterm + addons are vendored locally (vendor/javascript, pinned in
// importmap.rb) and imported statically above. The old build pulled them from
// jsdelivr at controller-connect time via injected <script>/<link> tags — a
// blocking, serial network round-trip on every terminal open. Same-origin
// modules load in parallel with the page (modulepreload) and are browser-cached,
// so the terminal now opens instantly.
export default class extends Controller {
  static targets = ["container"]
  static values  = { containerId: String, user: String, root: Boolean }

  connect() {
    this.#setupTerminal()
    this.#openSocket()
  }

  disconnect() {
    this.ws?.close()
    this.term?.dispose()
    this.resizeObserver?.disconnect()
  }

  #setupTerminal() {
    this.term = new Terminal({
      cursorBlink: true,
      fontFamily:  '"JetBrains Mono","Fira Code",Menlo,Monaco,Consolas,monospace',
      fontSize:    13,
      lineHeight:  1.25,
      scrollback:  5000,
      allowProposedApi: true,
      // Right-click is reserved for copy/paste (see #setupContextMenu); don't let
      // xterm hijack it to select a word.
      rightClickSelectsWord: false,
      theme: {
        background:         "#0d1117",
        foreground:         "#e6edf3",
        cursor:             "#58a6ff",
        cursorAccent:       "#0d1117",
        selectionBackground:"rgba(88,166,255,0.3)",
        black: "#484f58", red: "#ff7b72", green: "#3fb950", yellow: "#d29922",
        blue:  "#58a6ff", magenta: "#bc8cff", cyan: "#39c5cf", white: "#b1bac4",
        brightBlack: "#6e7681", brightRed: "#ffa198", brightGreen: "#56d364",
        brightYellow: "#e3b341", brightBlue: "#79c0ff", brightMagenta: "#d2a8ff",
        brightCyan: "#56d4dd", brightWhite: "#f0f6fc",
      }
    })

    this.fitAddon = new FitAddon()
    this.term.loadAddon(this.fitAddon)
    this.term.loadAddon(new WebLinksAddon())
    this.term.loadAddon(new ClipboardAddon())
    // NOTE: no WebglAddon — its glyph atlas leaves 2–3 rows overlapping when
    // output scrolls/reflows. The DOM renderer is plenty fast for a shell.

    this.term.open(this.containerTarget)
    this.fitAddon.fit()
    this.term.focus()
    this.containerTarget.addEventListener("click", () => this.term.focus())

    this.term.onData(data => this.#send(`${CMD_OUTPUT}${data}`))
    this.term.onResize(() => this.#sendResize())

    this.resizeObserver = new ResizeObserver(() => this.fitAddon.fit())
    this.resizeObserver.observe(this.containerTarget)

    this.#setupContextMenu()
    this.#setupKeyboardShortcuts()

    // The web font loads async (font-display: swap); xterm caches glyph metrics
    // at open(), so re-fit and repaint once the font is ready to fix character
    // alignment.
    if (document.fonts?.ready) {
      document.fonts.ready.then(() => {
        try { this.fitAddon.fit() } catch {}
        this.term?.refresh(0, (this.term.rows || 1) - 1)
      })
    }
  }

  #socketUrl() {
    const proto = location.protocol === "https:" ? "wss:" : "ws:"
    const qs    = this.rootValue ? "?root=1"
                : this.userValue ? `?user=${encodeURIComponent(this.userValue)}`
                : ""
    return `${proto}//${location.host}/containers/${this.containerIdValue}/ttyd-ws${qs}`
  }

  #openSocket() {
    // "tty" subprotocol is required by ttyd.
    this.ws = new WebSocket(this.#socketUrl(), ["tty"])
    this.ws.binaryType = "arraybuffer"

    this.ws.onopen = () => {
      // ttyd's initial JSON_DATA message — empty AuthToken (ttyd started
      // without --credential) plus the starting PTY dimensions.
      this.ws.send(JSON.stringify({ AuthToken: "", columns: this.term.cols, rows: this.term.rows }))
      this.term.write("\x1b[1;32m● Connected\x1b[0m\r\n")
      this.term.focus()
    }

    this.ws.onmessage = (e) => {
      const arr = new Uint8Array(e.data)
      if (arr.length === 0) return
      if (String.fromCharCode(arr[0]) === CMD_OUTPUT) this.term.write(arr.subarray(1))
      // SET_TITLE / SET_PREFERENCES are ignored — we own the chrome.
    }

    this.ws.onclose = () => this.term.write("\r\n\x1b[31m[disconnected]\x1b[0m\r\n")
    this.ws.onerror = () => this.term.write("\r\n\x1b[31m[connection error]\x1b[0m\r\n")
  }

  #send(str) {
    if (this.ws?.readyState === WebSocket.OPEN) this.ws.send(str)
  }

  #sendResize() {
    this.#send(`1${JSON.stringify({ columns: this.term.cols, rows: this.term.rows })}`)
  }

  // ── Keyboard shortcuts ──────────────────────────────────────────────────────

  #setupKeyboardShortcuts() {
    this.term.attachCustomKeyEventHandler((event) => {
      if (event.type !== "keydown") return true

      // Ctrl+C with active selection → copy (not SIGINT).
      if (event.ctrlKey && !event.shiftKey && !event.altKey && event.key === "c" && this.term.hasSelection()) {
        this.#copy(this.term.getSelection())
        this.term.clearSelection()
        return false
      }
      // Ctrl+Shift+C → copy selection.
      if (event.ctrlKey && event.shiftKey && event.key === "C") {
        const sel = this.term.getSelection()
        if (sel) { this.#copy(sel); this.term.clearSelection() }
        return false
      }
      // Ctrl+Shift+V → paste.
      if (event.ctrlKey && event.shiftKey && event.key === "V") {
        navigator.clipboard.readText().then(text => this.#send(`${CMD_OUTPUT}${text}`)).catch(() => {})
        return false
      }
      return true
    })
  }

  // ── Mouse: right-click copy/paste, auto-copy on select ──────────────────────

  #setupContextMenu() {
    // Capture phase fires before xterm's own mouse handlers on the child screen
    // element. Swallow the right button there so xterm never forwards it to the
    // PTY as a mouse-tracking report. Right button = copy/paste.
    const swallowRight = (e) => {
      if (e.button === 2) { e.preventDefault(); e.stopPropagation() }
    }
    this.containerTarget.addEventListener("mousedown", swallowRight, true)
    this.containerTarget.addEventListener("mouseup", swallowRight, true)

    // Auto-copy when a left-button drag finishes with text selected. Runs on
    // mouseup (selection finalized, still inside the user gesture) so the
    // clipboard write is allowed.
    this.containerTarget.addEventListener("mouseup", (e) => {
      if (e.button !== 0) return
      const sel = this.term.getSelection()
      if (sel) this.#writeClipboard(sel)
    })

    this.containerTarget.addEventListener("contextmenu", (e) => {
      e.preventDefault()
      e.stopPropagation()
      if (this.term.hasSelection()) {
        this.#copy(this.term.getSelection())
        this.term.clearSelection()
      } else {
        navigator.clipboard.readText().then(text => this.#send(`${CMD_OUTPUT}${text}`)).catch(() => {})
      }
      this.term.focus()
    }, true)
  }

  // ── Clipboard ───────────────────────────────────────────────────────────────

  #copy(text) {
    if (text) this.#writeClipboard(text)
  }

  // execCommand("copy") runs synchronously inside the user gesture and needs no
  // secure context — the most broadly reliable path, so try it first. The async
  // Clipboard API rejects in a later microtask, after the gesture's activation
  // has expired, so chaining it off a failed execCommand would itself be denied.
  #writeClipboard(text) {
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
}
