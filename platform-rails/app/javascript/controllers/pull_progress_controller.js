import { Controller } from "@hotwired/stimulus"

// Shows an animated in-progress banner while a Docker image pull is running.
// Attach to the pull form; banner appears on submit and disappears when Turbo
// replaces the page with the redirect response (which now includes the flash).
export default class extends Controller {
  connect() {
    this.handleStart = this.show.bind(this)
    this.element.addEventListener("turbo:submit-start", this.handleStart)
  }

  disconnect() {
    this.element.removeEventListener("turbo:submit-start", this.handleStart)
    document.getElementById("pull-progress-banner")?.remove()
  }

  show() {
    document.getElementById("pull-progress-banner")?.remove()

    const imageInput = this.element.querySelector('input[name="image"]')
    const tagInput   = this.element.querySelector('input[name="tag"]')
    const image = imageInput?.value?.trim() || "imagem"
    const tag   = tagInput?.value?.trim()   || "latest"

    const banner = document.createElement("div")
    banner.id = "pull-progress-banner"
    banner.className = [
      "mb-4 flex items-center gap-3 px-4 py-3 rounded-xl",
      "bg-cyan-50 dark:bg-cyan-950/40",
      "border border-cyan-200 dark:border-cyan-800/60",
      "text-cyan-700 dark:text-cyan-300",
      "animate-[fadeSlideIn_0.2s_ease-out]",
    ].join(" ")

    banner.innerHTML = `
      <svg class="animate-spin w-4 h-4 flex-shrink-0 text-cyan-500 dark:text-cyan-400"
           xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
        <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"/>
        <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8v8z"/>
      </svg>
      <div class="flex-1 min-w-0">
        <div class="text-sm font-medium leading-snug">Iniciando pull de <span class="font-mono">${image}:${tag}</span>…</div>
        <div class="text-xs opacity-70 mt-0.5">Aguarde, enfileirando job em background.</div>
        <div class="mt-2 h-1 rounded-full overflow-hidden bg-cyan-200 dark:bg-cyan-800/60">
          <div class="prune-progress-bar h-full w-1/3 rounded-full bg-gradient-to-r from-cyan-400 to-cyan-500 dark:from-cyan-500 dark:to-cyan-400"></div>
        </div>
      </div>
    `

    const frame = document.getElementById("images-content")
    if (frame) {
      frame.insertAdjacentElement("afterbegin", banner)
    }
  }
}
