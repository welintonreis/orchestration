import { Controller } from "@hotwired/stimulus"

// Scrolls its element to the bottom on connect. Re-fires automatically
// on every Turbo Frame reload, since the frame replaces this element's
// content wholesale and Stimulus reconnects it from scratch each time.
export default class extends Controller {
  connect() {
    this.element.scrollTop = this.element.scrollHeight
  }
}
