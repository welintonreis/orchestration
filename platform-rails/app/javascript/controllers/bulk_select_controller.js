import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["checkbox", "selectAll", "count", "btn"]
  static values  = { url: String }

  toggle() { this.#sync() }

  toggleAll() {
    const checked = this.selectAllTarget.checked
    this.checkboxTargets.forEach(cb => cb.checked = checked)
    this.#sync()
  }

  async perform(event) {
    const btn    = event.currentTarget
    const action = btn.dataset.bulkAction
    const ids    = this.checkboxTargets.filter(cb => cb.checked).map(cb => cb.value)
    if (!ids.length) return

    if ((action === "remove" || action === "kill") &&
        !confirm(`${action.charAt(0).toUpperCase() + action.slice(1)} ${ids.length} container(s)? This cannot be undone.`)) return

    const form  = document.createElement("form")
    form.method = "POST"
    form.action = this.urlValue

    const add = (name, value) => {
      const input = document.createElement("input")
      input.type  = "hidden"
      input.name  = name
      input.value = value
      form.appendChild(input)
    }

    add("authenticity_token", document.querySelector('meta[name="csrf-token"]').content)
    add("action_type", action)
    ids.forEach(id => add("ids[]", id))

    document.body.appendChild(form)
    form.submit()
  }

  #sync() {
    const total   = this.checkboxTargets.length
    const checked = this.checkboxTargets.filter(cb => cb.checked)
    const n       = checked.length

    if (this.hasCountTarget) {
      this.countTarget.textContent = n > 0 ? `${n} selected` : ""
      this.countTarget.classList.toggle("hidden", n === 0)
    }

    if (this.hasSelectAllTarget) {
      this.selectAllTarget.checked       = n === total && total > 0
      this.selectAllTarget.indeterminate = n > 0 && n < total
    }

    this.btnTargets.forEach(btn => {
      btn.disabled = n === 0
    })
  }
}
