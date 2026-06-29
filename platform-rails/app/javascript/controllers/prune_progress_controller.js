import { Controller } from "@hotwired/stimulus"

// Shows an animated in-progress banner while a Docker prune/batch-remove is
// running. Attach to a form; the banner is injected at the top of the
// images-content turbo-frame and disappears automatically when Turbo replaces
// the frame on the redirect response.
export default class extends Controller {
  static values = { label: String }

  connect() {
    this.handleStart = this.show.bind(this)
    this.element.addEventListener("turbo:submit-start", this.handleStart)
  }

  disconnect() {
    this.element.removeEventListener("turbo:submit-start", this.handleStart)
    document.getElementById("prune-progress-banner")?.remove()
  }

  show() {
    document.getElementById("prune-progress-banner")?.remove()

    const count = this.element.querySelectorAll('input[name="ids[]"]').length
    const noun  = count === 1 ? "imagem" : "imagens"
    const label = this.hasLabelValue ? this.labelValue : `${count} ${noun}`

    const banner = document.createElement("div")
    banner.id = "prune-progress-banner"
    banner.className = [
      "mb-4 flex items-center gap-3 px-4 py-3 rounded-xl",
      "bg-orange-50 dark:bg-orange-950/40",
      "border border-orange-200 dark:border-orange-800/60",
      "text-orange-700 dark:text-orange-300",
      "animate-[fadeSlideIn_0.2s_ease-out]",
    ].join(" ")

    banner.innerHTML = `
      <svg class="animate-spin w-4 h-4 flex-shrink-0 text-orange-500 dark:text-orange-400"
           xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
        <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"/>
        <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8v8z"/>
      </svg>
      <div class="flex-1 min-w-0">
        <div class="text-sm font-medium leading-snug">Removendo ${label}…</div>
        <div class="text-xs opacity-70 mt-0.5">Isso pode levar alguns segundos.</div>
        <div class="mt-2 h-1 rounded-full overflow-hidden bg-orange-200 dark:bg-orange-800/60">
          <div class="prune-progress-bar h-full w-1/3 rounded-full bg-gradient-to-r from-orange-400 to-orange-500 dark:from-orange-500 dark:to-orange-400"></div>
        </div>
      </div>
    `

    const frame = document.getElementById("images-content")
    if (frame) {
      frame.insertAdjacentElement("afterbegin", banner)
    } else {
      this.element.closest("turbo-frame")?.insertAdjacentElement("afterbegin", banner)
    }
  }
}
