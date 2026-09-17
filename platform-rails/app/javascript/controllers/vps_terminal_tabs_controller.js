import { Controller } from "@hotwired/stimulus"
import { confirmDialog, alertDialog } from "dialogs"

// Client-side tab switcher for terminal panes. Every pane stays mounted (and
// its SSH session connected); activating a tab only flips visibility.
export default class extends Controller {
  static targets = ["tab", "pane", "filesPane", "filesFrame", "resizeHandle"]
  static values  = { active: String }

  connect() {
    this.#apply(String(this.activeValue))
    this.filesOpen = false
    this.filesWidth = localStorage.getItem("vps_files_pane_width") || "42%"
  }

  // Hovering the button gives the iframe a head start loading before the
  // click lands — the visible "opening" lag was mostly this page's own
  // load, not the toggle animation.
  prefetchFiles(event) {
    if (!this.hasFilesFrameTarget || this.filesFrameTarget.src) return
    this.filesFrameTarget.src = event.currentTarget.dataset.filesUrl
  }

  // Split screen with the file explorer — frame src set lazily so it isn't
  // fetched until the user actually asks for it. Width driven from 0 so the
  // CSS transition on width/opacity actually animates (display:none can't).
  //
  // The src is set ONCE, ever. Two traps made every toggle refetch the whole
  // frame (HTML + JS boot + a fresh SSH listing, 0.7-3s of blank pane):
  // Turbo rewrites the attribute to an absolute URL after loading, so
  // comparing it against the relative dataset URL never matched; and the ✕
  // button carries no data-files-url, so closing assigned `undefined` and
  // Turbo *removed* the src. Reopening now costs a JSON refresh (~50ms) via
  // the file browser instead of the whole round trip.
  toggleFiles(event) {
    if (!this.hasFilesPaneTarget) return
    const url = event.currentTarget.dataset.filesUrl
    const loaded = !!this.filesFrameTarget.src
    if (url && !loaded) this.filesFrameTarget.src = url
    this.filesOpen = !this.filesOpen
    // Already-loaded frame shows a stale listing (the shell may have touched
    // the directory) — relist without re-rendering the frame.
    if (this.filesOpen && loaded) document.dispatchEvent(new CustomEvent("vps-files:reload"))
    this.filesPaneTarget.style.width = this.filesOpen ? this.filesWidth : "0"
    this.filesPaneTarget.style.minWidth = this.filesOpen ? "320px" : "0"
    this.filesPaneTarget.classList.toggle("opacity-0", !this.filesOpen)
    if (this.hasResizeHandleTarget) {
      this.resizeHandleTarget.style.width = this.filesOpen ? "4px" : "0"
      this.resizeHandleTarget.classList.toggle("opacity-0", !this.filesOpen)
    }
    requestAnimationFrame(() => this.paneTargets.forEach(p => p.dispatchEvent(new CustomEvent("terminal:activated"))))
    // Fit the terminal again once the width transition itself finishes.
    setTimeout(() => this.paneTargets.forEach(p => p.dispatchEvent(new CustomEvent("terminal:activated"))), 40)
  }

  // Drag the handle to resize the files split. Width set directly on the
  // pane; its own transition is suspended during the drag so it doesn't lag
  // 150ms behind the mouse. Iframe pointer-events killed too — fast moves
  // would otherwise get swallowed by its document.
  startResize(event) {
    event.preventDefault()
    this.filesPaneTarget.style.transition = "none"
    this.filesFrameTarget.style.pointerEvents = "none"
    const startX = event.clientX
    const startWidth = this.filesPaneTarget.getBoundingClientRect().width
    const onMove = (e) => {
      const w = Math.max(280, Math.min(startWidth - (e.clientX - startX), window.innerWidth - 320))
      this.filesPaneTarget.style.width = `${w}px`
    }
    const onUp = () => {
      document.removeEventListener("mousemove", onMove)
      document.removeEventListener("mouseup", onUp)
      this.filesPaneTarget.style.transition = ""
      this.filesFrameTarget.style.pointerEvents = ""
      this.filesWidth = this.filesPaneTarget.style.width
      localStorage.setItem("vps_files_pane_width", this.filesWidth)
      requestAnimationFrame(() => this.paneTargets.forEach(p => p.dispatchEvent(new CustomEvent("terminal:activated"))))
    }
    document.addEventListener("mousemove", onMove)
    document.addEventListener("mouseup", onUp)
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
    const msg = `Encerrar a sessão **#${id}**? O shell remoto e tudo que estiver rodando nele são destruídos.`
    if (!(await confirmDialog(msg, { titulo: "Encerrar sessão", ok: "Encerrar" }))) return

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
      alertDialog("Não foi possível encerrar a sessão.", { detalhe: e.message })
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
