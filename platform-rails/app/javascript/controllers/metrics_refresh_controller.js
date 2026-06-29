import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

export default class extends Controller {
  static values = {
    interval: { type: Number, default: 30000 },
    frame: { type: String, default: "" }
  }

  connect() {
    this.startTimer()
  }

  disconnect() {
    this.stopTimer()
  }

  // Fires whenever data-metrics-refresh-interval-value changes (e.g. via
  // the interval dropdown setting the attribute from Alpine.js).
  intervalValueChanged() {
    this.stopTimer()
    this.startTimer()
  }

  startTimer() {
    if (this.intervalValue <= 0) return  // 0 = paused
    this.timer = setInterval(() => this.refresh(), this.intervalValue)
  }

  stopTimer() {
    clearInterval(this.timer)
  }

  refresh() {
    if (document.hidden) return

    if (typeof this.element.reload === "function") {
      // turbo-frame element — reload the frame in place
      this.element.reload()
    } else if (this.frameValue) {
      // ponytail: set frame.src directly instead of Turbo.visit({frame:…})
      // to guarantee only this frame refreshes — Turbo.visit falls back to
      // a full-page visit if the frame lookup fails, which resets scroll.
      const frame = document.querySelector(`turbo-frame#${this.frameValue}`)
      if (frame) {
        frame.src = null
        frame.src = frame.getAttribute("src") || window.location.href
      }
    } else {
      Turbo.visit(window.location.href, { action: "replace" })
    }
  }
}
