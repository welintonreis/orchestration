import { Controller } from "@hotwired/stimulus"

// Client-side tab switcher for terminal panes. Every pane stays mounted (and
// its SSH session connected); activating a tab only flips visibility.
export default class extends Controller {
  static targets = ["tab", "pane"]
  static values  = { active: String }

  connect() {
    this.#apply(String(this.activeValue))
  }

  activate(event) {
    const id = event.currentTarget.dataset.sessionId
    this.#apply(id)
    const hostId = event.currentTarget.dataset.hostId
    if (hostId && id) {
      history.replaceState({}, "", `/vps_hosts/${hostId}/terminal_sessions/${id}/terminal`)
    }
  }

  async closeSession(event) {
    event.preventDefault()
    event.stopPropagation()
    const id = event.params?.sessionId || event.currentTarget.dataset.sessionId
    const hostId = event.params?.hostId || event.currentTarget.dataset.hostId
    const msg = `Fechar sessão #${id}? O shell continua vivo no host (tmux/dtach).`
    if (!window.confirm(msg)) return

    try {
      const r = await fetch(`/vps_hosts/${hostId}/terminal_sessions/${id}`, {
        method: "DELETE",
        headers: {
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content,
          "Accept": "application/json",
        },
      })
      if (!r.ok) throw new Error(`HTTP ${r.status}`)
    } catch (e) {
      alert(`Falha ao fechar: ${e.message}`)
      return
    }

    const wasActive = !this.paneTargets.find(p => p.dataset.sessionId === id)?.classList.contains("hidden")
    this.paneTargets.find(p => p.dataset.sessionId === id)?.remove()
    this.tabTargets.find(t => t.dataset.sessionId === id)?.remove()

    const remainingPanes = this.paneTargets
    if (!remainingPanes.length) { window.location.assign("/vps_hosts"); return }
    if (wasActive) {
      const nextPane = remainingPanes[remainingPanes.length - 1]
      const nextId = nextPane.dataset.sessionId
      const nextHostId = nextPane.dataset.hostId
      this.#apply(nextId)
      if (nextHostId && nextId) {
        history.replaceState({}, "", `/vps_hosts/${nextHostId}/terminal_sessions/${nextId}/terminal`)
      }
    }
  }

  #apply(id) {
    this.paneTargets.forEach(pane => {
      const on = pane.dataset.sessionId === id
      pane.classList.toggle("hidden", !on)
      pane.classList.toggle("flex", on)
      if (on) {
        pane.dispatchEvent(new CustomEvent("terminal:activated"))
      }
    })
    this.tabTargets.forEach(tab => {
      const on = tab.dataset.sessionId === id
      tab.classList.toggle("bg-surface-raised", on)
      tab.classList.toggle("border-b-2", on)
      tab.classList.toggle("border-b-cyan-500", on)
      tab.classList.toggle("text-text-primary", on)
      tab.classList.toggle("text-text-muted", !on)
    })
  }
}
