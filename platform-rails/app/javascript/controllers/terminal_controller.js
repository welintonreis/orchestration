import { Controller } from "@hotwired/stimulus"
import consumer from "channels/consumer"

const XTERM_VERSION    = "5.3.0"
const XTERM_FIT_VER    = "0.8.0"
const XTERM_CSS        = `https://cdn.jsdelivr.net/npm/xterm@${XTERM_VERSION}/css/xterm.css`
const XTERM_JS         = `https://cdn.jsdelivr.net/npm/xterm@${XTERM_VERSION}/lib/xterm.js`
const XTERM_FIT_JS     = `https://cdn.jsdelivr.net/npm/xterm-addon-fit@${XTERM_FIT_VER}/lib/xterm-addon-fit.js`

export default class extends Controller {
  static targets = ["container"]
  static values  = { containerId: String, endpoint: String, user: String }

  async connect() {
    await this.#loadAssets()
    this.#setupTerminal()
    this.#setupCable()
  }

  disconnect() {
    this.running = false
    this.subscription?.unsubscribe()
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

    this.term.onData(data => this.subscription?.perform("input", { text: data }))

    this.resizeObserver = new ResizeObserver(() => {
      this.fitAddon.fit()
      this.subscription?.perform("resize", { rows: this.term.rows, cols: this.term.cols })
    })
    this.resizeObserver.observe(this.containerTarget)
  }

  #setupCable() {
    this.subscription = consumer.subscriptions.create(
      { channel: "TerminalChannel", container_id: this.containerIdValue, endpoint: this.endpointValue, user: this.userValue || null },
      {
        connected:    ()     => this.term.write("\x1b[1;32m● Connected\x1b[0m\r\n"),
        disconnected: ()     => this.term.write("\r\n\x1b[31m[disconnected]\x1b[0m\r\n"),
        received:     (data) => {
          if (data.output) this.term.write(data.output)
          if (data.error)  this.term.write(`\r\n\x1b[31m[error] ${data.error}\x1b[0m\r\n`)
        }
      }
    )
  }
}
