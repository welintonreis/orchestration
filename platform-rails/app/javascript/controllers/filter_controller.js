import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "row"]

  filter() {
    const q = this.inputTarget.value.toLowerCase().trim()
    this.rowTargets.forEach((row) => {
      const name   = (row.dataset.name || "").toLowerCase()
      row.hidden   = q.length > 0 && !name.includes(q)
    })
  }

  clear() {
    this.inputTarget.value = ""
    this.filter()
  }
}
