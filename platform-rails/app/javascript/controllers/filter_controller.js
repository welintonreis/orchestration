import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// Server-side search (debounced) — searches every container, not just the
// ones already rendered on the current page. Was pure client-side filtering
// over rowTargets, which only ever covered whatever page size was visible.
export default class extends Controller {
  static targets = ["input"]
  static values = { url: String, frame: String }

  search() {
    clearTimeout(this.timeout)
    this.timeout = setTimeout(() => this.submit(), 300)
  }

  submit() {
    const url = new URL(this.urlValue, window.location.origin)
    const q = this.inputTarget.value.trim()
    if (q) url.searchParams.set("q", q)
    Turbo.visit(url.toString(), { frame: this.frameValue })
  }

  clear() {
    this.inputTarget.value = ""
    this.submit()
  }
}
