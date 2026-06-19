import { Controller } from "@hotwired/stimulus"

const SEGMENTS = 20

// Standalone segmented bar. Receives pct (0-100) via Stimulus value.
// Uses style.backgroundColor — no CSS class ordering dependency.
export default class extends Controller {
  static values = { pct: { type: Number, default: 0 } }

  connect()         { this.#render() }
  pctValueChanged() { this.#render() }

  #render() {
    const pct    = Math.min(Math.max(this.pctValue, 0), 100)
    const filled = Math.round(pct / 100 * SEGMENTS)
    const color  = pct >= 80 ? "var(--color-red-400)"
                 : pct >= 60 ? "var(--color-yellow-400)"
                 :              "var(--color-green-400)"

    if (this.element.children.length !== SEGMENTS) {
      this.element.innerHTML = Array.from({ length: SEGMENTS }, () =>
        `<span class="inline-block w-1 h-4 rounded-sm" style="transition: background-color 0.3s"></span>`
      ).join("")
    }

    Array.from(this.element.children).forEach((seg, i) => {
      seg.style.backgroundColor = i < filled ? color : "var(--color-surface-active)"
    })
  }
}
