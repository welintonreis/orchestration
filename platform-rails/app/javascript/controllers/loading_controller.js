import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  start(event) {
    const btn = event.currentTarget
    btn.disabled = true
    btn.dataset.originalText = btn.textContent.trim()
    btn.innerHTML = `<svg class="animate-spin w-3 h-3 inline" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24"><circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"/><path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8v8z"/></svg>`
  }
}
