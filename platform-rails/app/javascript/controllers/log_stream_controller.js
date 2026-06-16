import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"

const ERROR_RE  = /\b(error|exception|fatal|panic|critical)\b/i
const WARN_RE   = /\b(warn(?:ing)?|deprecated)\b/i
const TS_RE     = /^(\d{4}-\d{2}-\d{2}T[\d:.]+Z)\s/

export default class extends Controller {
  static targets = ["output", "search", "count", "scrollBtn"]
  static values  = { containerId: String, endpoint: String, tail: Number, timestamps: Boolean }

  connect() {
    this.lines      = []
    this.autoScroll = true
    this.consumer   = createConsumer()
    this.subscription = this.consumer.subscriptions.create(
      {
        channel:      "LogsChannel",
        container_id: this.containerIdValue,
        endpoint:     this.endpointValue,
        tail:         this.tailValue || 200,
        timestamps:   this.timestampsValue
      },
      {
        received: (data) => {
          if (data.error) {
            this.#addLine(`[error] ${data.error}`, "error")
          } else if (data.chunk) {
            data.chunk.split(/\r?\n/).forEach(line => {
              if (line) this.#addLine(line)
            })
          }
        }
      }
    )
  }

  disconnect() {
    this.subscription?.unsubscribe()
    this.consumer?.disconnect()
  }

  filter() {
    const q = this.searchTarget.value.trim().toLowerCase()
    const rows = this.outputTarget.querySelectorAll(".log-line")
    rows.forEach(row => {
      row.style.display = (!q || row.textContent.toLowerCase().includes(q)) ? "" : "none"
    })
  }

  toggleScroll() {
    this.autoScroll = !this.autoScroll
    this.scrollBtnTarget.classList.toggle("bg-cyan-900/30", this.autoScroll)
    this.scrollBtnTarget.classList.toggle("text-cyan-400",  this.autoScroll)
    this.scrollBtnTarget.classList.toggle("text-gray-500",  !this.autoScroll)
    if (this.autoScroll) this.#scrollToBottom()
  }

  clear() {
    this.lines = []
    this.outputTarget.innerHTML = ""
    this.#updateCount()
  }

  #addLine(text, forceClass = null) {
    this.lines.push(text)
    this.#updateCount()

    const span = document.createElement("span")
    span.className = "log-line block"

    let cls = forceClass
    if (!cls) {
      if (ERROR_RE.test(text)) cls = "error"
      else if (WARN_RE.test(text)) cls = "warn"
    }

    if (cls === "error") {
      span.classList.add("text-red-400")
    } else if (cls === "warn") {
      span.classList.add("text-yellow-400")
    } else {
      span.classList.add("text-gray-300")
    }

    if (this.timestampsValue) {
      const m = text.match(TS_RE)
      if (m) {
        const tsSpan  = document.createElement("span")
        const msgSpan = document.createElement("span")
        tsSpan.className  = "text-gray-600 select-none mr-2"
        tsSpan.textContent = m[1]
        msgSpan.textContent = text.slice(m[0].length)
        span.appendChild(tsSpan)
        span.appendChild(msgSpan)
      } else {
        span.textContent = text
      }
    } else {
      span.textContent = text
    }

    this.outputTarget.appendChild(span)
    this.#applyFilter(span)

    if (this.autoScroll) this.#scrollToBottom()
  }

  #applyFilter(span) {
    const q = this.hasSearchTarget ? this.searchTarget.value.trim().toLowerCase() : ""
    if (q && !span.textContent.toLowerCase().includes(q)) span.style.display = "none"
  }

  #scrollToBottom() {
    const el = this.outputTarget
    el.scrollTop = el.scrollHeight
  }

  #updateCount() {
    if (this.hasCountTarget) this.countTarget.textContent = this.lines.length
  }
}
