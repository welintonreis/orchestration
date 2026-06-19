import { Controller } from "@hotwired/stimulus"

const XTERM_VERSION = "5.3.0"
const XTERM_FIT_VER = "0.8.0"
const XTERM_CSS     = `https://cdn.jsdelivr.net/npm/xterm@${XTERM_VERSION}/css/xterm.css`
const XTERM_JS      = `https://cdn.jsdelivr.net/npm/xterm@${XTERM_VERSION}/lib/xterm.js`
const XTERM_FIT_JS  = `https://cdn.jsdelivr.net/npm/xterm-addon-fit@${XTERM_FIT_VER}/lib/xterm-addon-fit.js`

// ttyd wire protocol (command = first byte of each message).
// Client → server: INPUT "0", RESIZE "1"+JSON, initial JSON_DATA "{...}".
// Server → client: OUTPUT "0", SET_TITLE "1", SET_PREFERENCES "2".
const CMD_OUTPUT = "0"

export default class extends Controller {
  static targets = ["container"]
  static values  = { containerId: String, user: String, root: Boolean }

  async connect() {
    await this.#loadAssets()
    this.#setupTerminal()
    this.#openSocket()
  }

  disconnect() {
    this.subprotocolReady = false
    this.ws?.close()
    this.term?.dispose()
    this.resizeObserver?.disconnect()
  }

  #loadAssets() {
    return Promise.all([
      this.#loadStyle(XTERM_CSS),
      this.#loadScript(XTERM_JS).then(() => this.#loadScript(XTERM_FIT_JS))
    ])
  }

  #loadScript(src) {
    if (document.querySelector(`script[src="${src}"]`)) return Promise.resolve()
    return new Promise((res, rej) => {
      const s = Object.assign(document.createElement("script"), { src, onload: res, onerror: rej })
      document.head.appendChild(s)
    })
  }

  #loadStyle(href) {
    if (document.querySelector(`link[href="${href}"]`)) return Promise.resolve()
    return new Promise(res => {
      const l = Object.assign(document.createElement("link"), { rel: "stylesheet", href, onload: res })
      document.head.appendChild(l)
    })
  }

  #setupTerminal() {
    this.term = new Terminal({
      cursorBlink: true,
      fontFamily:  '"JetBrains Mono","Fira Code",Menlo,Monaco,Consolas,monospace',
      fontSize:    13,
      lineHeight:  1.25,
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

    this.fitAddon = new FitAddon.FitAddon()
    this.term.loadAddon(this.fitAddon)
    this.term.open(this.containerTarget)
    this.fitAddon.fit()

    this.term.onData(data => this.#send(`0${data}`))

    this.resizeObserver = new ResizeObserver(() => {
      this.fitAddon.fit()
      this.#sendResize()
    })
    this.resizeObserver.observe(this.containerTarget)
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
}
