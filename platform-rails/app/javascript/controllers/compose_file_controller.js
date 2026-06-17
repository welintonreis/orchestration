import { Controller } from "@hotwired/stimulus"

// Backs the "Arquivo Compose" field on git_stacks/new — once a Git
// connection is picked, fetches the repo's yml/yaml file list and shows
// matching suggestions + a found/not-found indicator as the user types.
export default class extends Controller {
  static targets = ["connectionSelect", "input", "suggestions", "indicator"]
  static values = { urlTemplate: String }

  connect() {
    this.files = null
    this.loading = false
  }

  async loadFiles() {
    const connId = this.connectionSelectTarget.value
    this.files = null
    this.renderIndicator()
    if (!connId) return

    this.loading = true
    const url = this.urlTemplateValue.replace("__ID__", connId)
    try {
      const res = await fetch(url, { headers: { Accept: "application/json" } })
      this.files = res.ok ? await res.json() : []
    } catch {
      this.files = []
    }
    this.loading = false
    this.filter()
  }

  filter() {
    if (!Array.isArray(this.files)) {
      this.suggestionsTarget.classList.add("hidden")
      this.renderIndicator()
      return
    }
    const q = this.inputTarget.value.trim().toLowerCase()
    const matches = q ? this.files.filter((f) => f.toLowerCase().includes(q)) : this.files
    if (matches.length > 0 && document.activeElement === this.inputTarget) {
      this.suggestionsTarget.innerHTML = matches
        .slice(0, 8)
        .map((f) => `<div class="px-3 py-1.5 text-sm text-gray-300 hover:bg-gray-800 cursor-pointer font-mono" data-action="mousedown->compose-file#pick" data-file="${f}">${f}</div>`)
        .join("")
      this.suggestionsTarget.classList.remove("hidden")
    } else {
      this.suggestionsTarget.classList.add("hidden")
    }
    this.renderIndicator()
  }

  pick(event) {
    this.inputTarget.value = event.currentTarget.dataset.file
    this.suggestionsTarget.classList.add("hidden")
    this.renderIndicator()
  }

  blur() {
    setTimeout(() => this.suggestionsTarget.classList.add("hidden"), 150)
  }

  renderIndicator() {
    const val = this.inputTarget.value.trim()
    if (this.loading) {
      this.indicatorTarget.innerHTML = `<span class="inline-block w-3.5 h-3.5 rounded-full border-2 border-gray-600 border-t-gray-300 animate-spin"></span>`
      return
    }
    if (!val || !Array.isArray(this.files)) {
      this.indicatorTarget.innerHTML = ""
      return
    }
    const exists = this.files.includes(val)
    this.indicatorTarget.innerHTML = exists
      ? `<svg class="w-4 h-4 text-green-500" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2.5"><path stroke-linecap="round" stroke-linejoin="round" d="M5 13l4 4L19 7"/></svg>`
      : `<svg class="w-4 h-4 text-red-500" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2.5"><path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12"/></svg>`
  }
}
