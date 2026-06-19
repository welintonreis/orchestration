import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

export default class extends Controller {
  static values = { interval: { type: Number, default: 30000 } }

  connect() {
    this.timer = setInterval(() => {
      if (typeof this.element.reload === "function") {
        // turbo-frame element — reload the frame in place
        this.element.reload()
      } else {
        // plain element — replace the full page via Turbo (no blank flash)
        Turbo.visit(window.location.href, { action: "replace" })
      }
    }, this.intervalValue)
  }

  disconnect() {
    clearInterval(this.timer)
  }
}
