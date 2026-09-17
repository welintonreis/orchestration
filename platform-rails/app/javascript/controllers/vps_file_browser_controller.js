import { Controller } from "@hotwired/stimulus"
import { confirmDialog, promptDialog, alertDialog } from "dialogs"

const IMAGE_EXT = ["png", "jpg", "jpeg", "gif", "svg", "webp"]
const TEXT_EXT   = ["rb","js","ts","erb","html","css","scss","json","yml","yaml","md","txt","sh",
                     "conf","cfg","ini","env","py","go","rs","java","c","h","cpp","sql","xml","log","gitignore"]

// Windows-Explorer-style file browser over a VpsHost's real filesystem (SFTP).
// Ported from redhusky-remote-ssh's file_browser_controller.js, retargeted to
// a host-scoped URL (/vps_hosts/:id/files) instead of session-scoped, plus
// view modes (list/grid/details) and a preview modal.
export default class extends Controller {
  static targets = [
    "breadcrumb", "filter", "list", "progress", "hiddenBtn",
    "viewBtnList", "viewBtnGrid", "viewBtnDetails",
    "thumbBtnSm", "thumbBtnMd", "thumbBtnLg",
    "pasteBar", "clipName", "bulkBar", "bulkCount",
    "previewModal", "previewTitle", "previewBody", "previewDownloadBtn",
  ]
  static values = { hostId: String, seed: Object }

  connect() {
    this.path = ""
    this.entries = []
    this.filterText = ""
    this.showHidden = false
    this.showThumbnails = localStorage.getItem("tb:vpsfiles:thumbs") === "true"
    this.thumbSize = localStorage.getItem("tb:vpsfiles:thumb_size") || "sm" // sm (1x), md (2x), lg (5x)
    this.selection = new Set()
    this.cursor = -1
    this.clipboard = null // { mode: "copy"|"cut", path, name }
    this.viewMode = localStorage.getItem("tb:vpsfiles:view") || "list"
    // The terminal's split-screen toggle reopens an already-loaded frame and
    // asks for a relist instead of refetching the whole frame.
    this._onReload = () => this.load()
    document.addEventListener("vps-files:reload", this._onReload)
    // The page already carries the first listing (see VpsFilesController#index)
    // — paint it instead of spending a second round trip to fetch what we have.
    if (this.seedValue?.path) {
      this.path = this.seedValue.path
      this.entries = this.seedValue.entries || []
      this._renderBreadcrumb()
      this._render()
    } else {
      this.load()
    }
  }

  disconnect() {
    document.removeEventListener("vps-files:reload", this._onReload)
  }

  // ── navigation ──────────────────────────────────────────────────────────

  async load(path = this.path) {
    this.selection.clear()
    this.cursor = -1
    this._progress("Carregando…")
    try {
      const params = path ? { path } : {}
      const res = await this._get("", params)
      this.path = res.path || path || "/"
      this.entries = res.entries || []
      this._renderBreadcrumb()
      this._render()
      this._progress(null)
    } catch (e) {
      this._progress(`Erro: ${e.message}`)
    }
  }

  navigate(event) {
    const path = event.currentTarget.dataset.path
    if (path != null) this.load(path)
  }

  open(entry) {
    if (!entry) return
    if (entry.type === "directory") {
      if (this._loadingPath === entry.path) return
      this._loadingPath = entry.path
      this.load(entry.path).finally(() => { this._loadingPath = null })
    } else {
      this.openPreview(entry)
    }
  }

  // ── toolbar ─────────────────────────────────────────────────────────────

  setFilter(event) { this.filterText = event.target.value.toLowerCase(); this._render() }

  toggleHidden() {
    this.showHidden = !this.showHidden
    this.hiddenBtnTarget.classList.toggle("text-cyan-500", this.showHidden)
    this._render()
  }

  toggleThumbnails() {
    this.showThumbnails = !this.showThumbnails
    localStorage.setItem("tb:vpsfiles:thumbs", this.showThumbnails)
    this._render()
  }

  setThumbSize(event) {
    this.thumbSize = event.params.size
    localStorage.setItem("tb:vpsfiles:thumb_size", this.thumbSize)
    this._render()
  }

  setViewMode(event) {
    this.viewMode = event.params.mode
    localStorage.setItem("tb:vpsfiles:view", this.viewMode)
    this._render()
  }

  async newFolder() {
    const name = await promptDialog("Nome da nova pasta:", "", { titulo: "Nova pasta", ok: "Criar" })
    if (!name) return
    this._progress("Criando pasta…")
    try { await this._post("mkdir", { path: this.path, name }); await this.load() }
    catch (e) { alertDialog(`Falha: ${e.message}`) }
    finally { this._progress(null) }
  }

  async upload(event) {
    const files = [...event.target.files]
    if (!files.length) return
    const fd = new FormData()
    fd.append("path", this.path)
    files.forEach(f => fd.append("files[]", f))
    this._progress(`Enviando ${files.length} arquivo(s)…`)
    try {
      await fetch(this._url("upload"), { method: "POST", headers: this._csrfHeaders(), body: fd })
      await this.load()
    } catch (e) { alertDialog(`Upload falhou: ${e.message}`) }
    finally { this._progress(null); event.target.value = "" }
  }

  // ── selection ───────────────────────────────────────────────────────────

  rowClick(event) {
    if (event.target.closest("button, a, input")) return

    const path = event.currentTarget.dataset.path
    const idx  = this.entries.findIndex(e => e.path === path)
    const entry = this.entries[idx]
    if (!entry) return

    // Double click fallback
    if (event.detail === 2) {
      this.open(entry)
      return
    }

    if (event.shiftKey && this.cursor >= 0) {
      const [a, b] = [this.cursor, idx].sort((x, y) => x - y)
      this.selection = new Set(this.entries.slice(a, b + 1).map(e => e.path))
      this.cursor = idx
      this._renderSelection()
      return
    }
    if (event.ctrlKey || event.metaKey) {
      this.selection.has(path) ? this.selection.delete(path) : this.selection.add(path)
      this.cursor = idx
      this._renderSelection()
      return
    }

    // Single click on file or folder: selects it
    this.selection = new Set([path])
    this.cursor = idx
    this._renderSelection()
  }

  _renderSelection() {
    const items = this.listTarget.querySelectorAll("[data-path]")
    items.forEach(el => {
      const isSel = this.selection.has(el.dataset.path)
      if (this.viewMode === "grid") {
        el.classList.toggle("bg-cyan-500/10", isSel)
        el.classList.toggle("border-cyan-500/30", isSel)
        el.classList.toggle("border-transparent", !isSel)
        el.classList.toggle("hover:bg-surface-active/50", !isSel)
        el.classList.toggle("hover:border-border-subtle", !isSel)
      } else {
        el.classList.toggle("bg-cyan-500/10", isSel)
        el.classList.toggle("hover:bg-surface-active/50", !isSel)
      }
    })
    this._renderBulkBar()
  }

  clearSelection() { this.selection.clear(); this._renderSelection() }

  keydown(event) {
    if (!this.entries.length) return
    const visible = this._visibleEntries()
    if (event.key === "ArrowDown" || event.key === "ArrowUp") {
      event.preventDefault()
      this.cursor = Math.min(Math.max((event.key === "ArrowDown" ? this.cursor + 1 : this.cursor - 1), 0), visible.length - 1)
      this.selection = new Set([visible[this.cursor]?.path].filter(Boolean))
      this._renderSelection()
    } else if (event.key === "Enter" && this.cursor >= 0) {
      this.open(visible[this.cursor])
    } else if (event.key === "Backspace") {
      if (this.path !== "/") this.load(this.path.split("/").slice(0, -1).join("/") || "/")
    } else if (event.key === "Delete") {
      if (this.selection.size) this.bulkDelete()
    } else if (event.key === "F2" && this.cursor >= 0) {
      this.rename({ currentTarget: { dataset: { path: visible[this.cursor].path, name: visible[this.cursor].name } } })
    } else if (event.key === " " && this.cursor >= 0) {
      event.preventDefault()
      const path = visible[this.cursor].path
      this.selection.has(path) ? this.selection.delete(path) : this.selection.add(path)
      this._renderSelection()
    }
  }

  // ── file ops ────────────────────────────────────────────────────────────

  download(event) {
    event?.stopPropagation()
    const path = event.currentTarget.dataset.path
    window.location = `${this._url("download")}?path=${encodeURIComponent(path)}`
  }

  downloadArchive(event) {
    event?.stopPropagation()
    const path = event.currentTarget.dataset.path
    window.location = `${this._url("archive")}?path=${encodeURIComponent(path)}`
  }

  downloadSelectionArchive() {
    if (!this.selection.size) return
    // Single plain file → stream it directly, no point tar.gz-wrapping one file.
    if (this.selection.size === 1) {
      const entry = this.entries.find(e => e.path === [...this.selection][0])
      if (entry && entry.type !== "directory") {
        window.location = `${this._url("download")}?path=${encodeURIComponent(entry.path)}`
        return
      }
    }
    const qs = [...this.selection].map(p => `paths[]=${encodeURIComponent(p)}`).join("&")
    window.location = `${this._url("archive")}?${qs}`
  }

  async copyPath(event) {
    event?.stopPropagation()
    const path = event.currentTarget.dataset.path
    try {
      await navigator.clipboard.writeText(path)
    } catch {
      this._fallbackCopy(path)
    }
    this._showFeedback(event.currentTarget, "Caminho copiado!")
  }

  async bulkCopyPath(event) {
    event?.stopPropagation()
    if (!this.selection.size) return
    const text = [...this.selection].join("\n")
    try {
      await navigator.clipboard.writeText(text)
    } catch {
      this._fallbackCopy(text)
    }
    this._showFeedback(event?.currentTarget, "Caminhos copiados!")
  }

  // clipboard.paths is always an array — single-item cut/copy just wraps one
  // path, so paste() has one code path for both.
  cut(event)  {
    event?.stopPropagation()
    const name = event.currentTarget.dataset.name
    this.clipboard = { mode: "cut",  paths: [event.currentTarget.dataset.path], names: [name] }
    this._renderClipboard()
    this._showFeedback(event.currentTarget, `"${name}" recortado!`)
  }
  copy(event) {
    event?.stopPropagation()
    const name = event.currentTarget.dataset.name
    this.clipboard = { mode: "copy", paths: [event.currentTarget.dataset.path], names: [name] }
    this._renderClipboard()
    this._showFeedback(event.currentTarget, `"${name}" copiado!`)
  }
  bulkCut(event)  {
    event?.stopPropagation()
    if (this.selection.size) {
      this.clipboard = { mode: "cut",  paths: [...this.selection], names: this._selectionNames() }
      this._renderClipboard()
      this._showFeedback(event?.currentTarget, `${this.selection.size} item(ns) recortado(s)!`)
    }
  }
  bulkCopy(event) {
    event?.stopPropagation()
    if (this.selection.size) {
      this.clipboard = { mode: "copy", paths: [...this.selection], names: this._selectionNames() }
      this._renderClipboard()
      this._showFeedback(event?.currentTarget, `${this.selection.size} item(ns) copiado(s)!`)
    }
  }
  clearClipboard() { this.clipboard = null; this._renderClipboard() }

  _fallbackCopy(text) {
    const ta = document.createElement("textarea")
    ta.value = text
    ta.style.position = "fixed"
    ta.style.opacity = "0"
    document.body.appendChild(ta)
    ta.select()
    try { document.execCommand("copy") } catch {}
    document.body.removeChild(ta)
  }

  _showFeedback(btn, message = "Copiado!") {
    this._showToast(message)
    if (!btn) return
    const originalHtml = btn.innerHTML
    const originalTitle = btn.getAttribute("title")

    if (btn.querySelector("svg") && !btn.innerText.trim()) {
      btn.innerHTML = `<svg class="w-3.5 h-3.5 text-emerald-500 shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2.5"><path stroke-linecap="round" stroke-linejoin="round" d="M5 13l4 4L19 7"/></svg>`
    } else {
      btn.innerHTML = `<span class="inline-flex items-center gap-1 text-emerald-500 font-medium"><svg class="w-3.5 h-3.5 shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2.5"><path stroke-linecap="round" stroke-linejoin="round" d="M5 13l4 4L19 7"/></svg> ${message}</span>`
    }
    btn.setAttribute("title", message)
    btn.classList.add("text-emerald-500")

    setTimeout(() => {
      btn.innerHTML = originalHtml
      if (originalTitle) btn.setAttribute("title", originalTitle)
      else btn.removeAttribute("title")
      btn.classList.remove("text-emerald-500")
    }, 1500)
  }

  _showToast(msg) {
    let toast = this.element.querySelector(".vps-fb-toast")
    if (!toast) {
      toast = document.createElement("div")
      toast.className = "vps-fb-toast fixed bottom-4 right-4 z-50 flex items-center gap-2 px-3 py-2 bg-surface-raised/95 border border-emerald-500/40 shadow-xl rounded-lg text-xs font-medium text-text-primary backdrop-blur-sm pointer-events-none transition-all duration-200 opacity-0 translate-y-2"
      this.element.appendChild(toast)
    }
    toast.innerHTML = `<svg class="w-4 h-4 text-emerald-500 shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2.5"><path stroke-linecap="round" stroke-linejoin="round" d="M5 13l4 4L19 7"/></svg> <span>${this._esc(msg)}</span>`
    toast.classList.remove("opacity-0", "translate-y-2")
    toast.classList.add("opacity-100", "translate-y-0")

    if (this._toastTimer) clearTimeout(this._toastTimer)
    this._toastTimer = setTimeout(() => {
      toast.classList.remove("opacity-100", "translate-y-0")
      toast.classList.add("opacity-0", "translate-y-2")
    }, 2000)
  }

  _selectionNames() {
    return [...this.selection].map(p => this.entries.find(e => e.path === p)?.name || p)
  }

  async paste() {
    if (!this.clipboard) return
    const { mode, paths } = this.clipboard
    this._progress(mode === "cut" ? "Movendo…" : "Copiando…")
    try {
      // Backend move/copy take one path each — no bulk endpoint, so a
      // multi-selection pastes sequentially. Small N (a selection), fine.
      for (const path of paths) await this._post(mode === "cut" ? "move" : "copy", { path, dest: this.path })
      this.clipboard = null
      this._renderClipboard()
      this.clearSelection()
      await this.load()
    } catch (e) { alertDialog(`Falha: ${e.message}`) }
    finally { this._progress(null) }
  }

  async rename(event) {
    event?.stopPropagation()
    const path = event.currentTarget.dataset.path
    const atual = event.currentTarget.dataset.name
    const name = await promptDialog("Novo nome:", atual, { titulo: "Renomear", semExtensao: true })
    if (!name || name === atual) return
    try { await this._patch("rename", { path, name }); await this.load() }
    catch (e) { alertDialog(`Falha: ${e.message}`) }
  }

  async destroy(event) {
    event?.stopPropagation()
    const path = event.currentTarget.dataset.path
    if (!(await confirmDialog(`Apagar "${event.currentTarget.dataset.name}"?`, { ok: "Apagar" }))) return
    this._progress("Apagando…")
    try { await this._delete([path]); await this.load() }
    catch (e) { alertDialog(`Falha: ${e.message}`) }
    finally { this._progress(null) }
  }

  async bulkDelete() {
    if (!this.selection.size) return
    if (!(await confirmDialog(`Apagar ${this.selection.size} item(ns)?`, { ok: "Apagar" }))) return
    this._progress("Apagando…")
    try { await this._delete([...this.selection]); await this.load() }
    catch (e) { alertDialog(`Falha: ${e.message}`) }
    finally { this._progress(null) }
  }

  // ── preview ─────────────────────────────────────────────────────────────

  async openPreview(entry) {
    const ext = entry.name.split(".").pop().toLowerCase()
    this.previewTitleTarget.textContent = entry.name
    this.previewDownloadBtnTarget.onclick = () => { window.location = `${this._url("download")}?path=${encodeURIComponent(entry.path)}` }
    this.previewModalTarget.classList.remove("hidden")

    if (IMAGE_EXT.includes(ext)) {
      this.previewBodyTarget.innerHTML = `<img src="${this._url("raw")}?path=${encodeURIComponent(entry.path)}" class="max-w-full max-h-[65vh] mx-auto rounded">`
      return
    }
    if (TEXT_EXT.includes(ext) || entry.size < 65536) {
      this.previewBodyTarget.innerHTML = `<span class="text-text-muted">Carregando…</span>`
      try {
        const res = await this._get("content", { path: entry.path })
        const pre = document.createElement("pre")
        pre.className = "whitespace-pre-wrap break-words font-mono text-xs text-text-primary"
        pre.textContent = res.content
        this.previewBodyTarget.innerHTML = ""
        this.previewBodyTarget.appendChild(pre)
      } catch (e) {
        this.previewBodyTarget.innerHTML = `<span class="text-red-500">${e.message}</span>`
      }
      return
    }
    this.previewBodyTarget.innerHTML = `<span class="text-text-muted">Sem preview para este tipo — use o botão Baixar.</span>`
  }

  closePreview() { this.previewModalTarget.classList.add("hidden") }

  // ── rendering ───────────────────────────────────────────────────────────

  _visibleEntries() {
    return this.entries.filter(e => {
      if (!this.showHidden && e.name.startsWith(".")) return false
      if (this.filterText && !e.name.toLowerCase().includes(this.filterText)) return false
      return true
    })
  }

  _render() {
    const list = this._visibleEntries()
    ;[["viewBtnList", "list"], ["viewBtnGrid", "grid"], ["viewBtnDetails", "details"]].forEach(([t, m]) => {
      this[`${t}Target`]?.classList.toggle("bg-surface-active", this.viewMode === m)
    })
    ;[["thumbBtnSm", "sm"], ["thumbBtnMd", "md"], ["thumbBtnLg", "lg"]].forEach(([t, s]) => {
      this[`${t}Target`]?.classList.toggle("bg-surface-active", this.thumbSize === s)
      this[`${t}Target`]?.classList.toggle("text-cyan-500", this.showThumbnails && this.thumbSize === s)
    })
    const thumbBtn = this.element.querySelector("[data-action*='toggleThumbnails']")
    thumbBtn?.classList.toggle("text-cyan-500", this.showThumbnails)
    thumbBtn?.classList.toggle("bg-surface-active", this.showThumbnails)

    if (!list.length) {
      this.listTarget.innerHTML = `<div class="py-10 text-center text-sm text-text-muted">Pasta vazia</div>`
    } else if (this.viewMode === "grid") {
      this.listTarget.innerHTML = `<div class="flex flex-wrap gap-2.5 p-3">${list.map(e => this._gridTile(e)).join("")}</div>`
    } else if (this.viewMode === "details") {
      this.listTarget.innerHTML = this._detailsTable(list)
    } else {
      this.listTarget.innerHTML = list.map(e => this._listRow(e)).join("")
    }
    this._renderBulkBar()
  }

  _icon(entry, large = false) {
    if (entry.type === "directory") {
      let sz = "w-4 h-4"
      if (large) {
        if (this.thumbSize === "lg") sz = "w-24 h-24"
        else if (this.thumbSize === "md") sz = "w-16 h-16"
        else sz = "w-10 h-10"
      }
      return `<svg class="${sz} text-cyan-500 shrink-0" fill="currentColor" viewBox="0 0 24 24"><path d="M10 4H4a2 2 0 00-2 2v12a2 2 0 002 2h16a2 2 0 002-2V8a2 2 0 00-2-2h-8l-2-2z"/></svg>`
    }
    const ext = entry.name.split(".").pop().toLowerCase()
    if (this.showThumbnails && IMAGE_EXT.includes(ext)) {
      let cls = "w-6 h-6 object-cover rounded shrink-0 border border-border-subtle"
      if (large) {
        if (this.thumbSize === "lg") cls = "w-48 h-48 object-cover rounded shadow-md border border-border-subtle"
        else if (this.thumbSize === "md") cls = "w-28 h-28 object-cover rounded shadow border border-border-subtle"
        else cls = "w-16 h-16 object-cover rounded shadow-sm border border-border-subtle"
      } else {
        if (this.thumbSize === "lg") cls = "w-14 h-14 object-cover rounded shrink-0 border border-border-subtle"
        else if (this.thumbSize === "md") cls = "w-10 h-10 object-cover rounded shrink-0 border border-border-subtle"
      }
      return `<img src="${this._url("raw")}?path=${encodeURIComponent(entry.path)}" class="${cls}" loading="lazy">`
    }
    let sz = "w-4 h-4"
    if (large) {
      if (this.thumbSize === "lg") sz = "w-24 h-24"
      else if (this.thumbSize === "md") sz = "w-16 h-16"
      else sz = "w-10 h-10"
    }
    return `<svg class="${sz} text-text-muted shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M7 3h7l5 5v13a1 1 0 01-1 1H7a1 1 0 01-1-1V4a1 1 0 011-1z"/><path stroke-linecap="round" stroke-linejoin="round" d="M14 3v5h5"/></svg>`
  }

  _linkIcon() {
    return `<svg class="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M10 13a5 5 0 007.07 0l1.93-1.93a5 5 0 00-7.07-7.07L10.5 5.5"/><path stroke-linecap="round" stroke-linejoin="round" d="M14 11a5 5 0 00-7.07 0l-1.93 1.93a5 5 0 007.07 7.07L13.5 18.5"/></svg>`
  }

  _actions(e) {
    return `
      <button data-action="click->vps-file-browser#copyPath" data-path="${e.path}" title="Copiar caminho" class="p-1 text-text-muted hover:text-text-primary">
        ${this._linkIcon()}
      </button>
      <button data-action="click->vps-file-browser#cut" data-path="${e.path}" data-name="${e.name}" title="Recortar" class="p-1 text-text-muted hover:text-text-primary">
        <svg class="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><circle cx="6" cy="6" r="3"/><circle cx="6" cy="18" r="3"/><path d="M20 4L8.12 15.88M14.47 14.48L20 20M8.12 8.12L12 12"/></svg>
      </button>
      <button data-action="click->vps-file-browser#copy" data-path="${e.path}" data-name="${e.name}" title="Copiar" class="p-1 text-text-muted hover:text-text-primary">
        <svg class="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><rect x="9" y="9" width="11" height="11" rx="1"/><path d="M5 15V5a2 2 0 012-2h10"/></svg>
      </button>
      <button data-action="click->vps-file-browser#rename" data-path="${e.path}" data-name="${e.name}" title="Renomear" class="p-1 text-text-muted hover:text-text-primary">
        <svg class="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5M18.5 2.5a2.12 2.12 0 013 3L12 15l-4 1 1-4 9.5-9.5z"/></svg>
      </button>
      ${e.type === "directory"
        ? `<button data-action="click->vps-file-browser#downloadArchive" data-path="${e.path}" title="Baixar .tar.gz" class="p-1 text-text-muted hover:text-text-primary">${this._dlIcon()}</button>`
        : `<button data-action="click->vps-file-browser#download" data-path="${e.path}" title="Baixar" class="p-1 text-text-muted hover:text-text-primary">${this._dlIcon()}</button>`}
      <button data-action="click->vps-file-browser#destroy" data-path="${e.path}" data-name="${e.name}" title="Apagar" class="p-1 text-text-muted hover:text-red-500">
        <svg class="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M6 7h12M9 7V4h6v3m-8 0v13a1 1 0 001 1h8a1 1 0 001-1V7"/></svg>
      </button>`
  }

  _dlIcon() {
    return `<svg class="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M12 3v13m0 0l-4-4m4 4l4-4M4 21h16"/></svg>`
  }

  _listRow(e) {
    const sel = this.selection.has(e.path)
    return `
      <div class="group flex items-center gap-2.5 px-3 py-1.5 cursor-pointer border-b border-border-subtle/50 last:border-0 ${sel ? "bg-cyan-500/10" : "hover:bg-surface-active/50"}"
           data-path="${e.path}" data-action="click->vps-file-browser#rowClick dblclick->vps-file-browser#openFromRow">
        ${this._icon(e)}
        <span class="flex-1 min-w-0 truncate text-sm text-text-primary">${this._esc(e.name)}</span>
        <span class="text-xs text-text-muted w-16 text-right shrink-0">${e.type === "directory" ? "" : this._humanSize(e.size)}</span>
        <div class="hidden group-hover:flex items-center gap-0.5 shrink-0">${this._actions(e)}</div>
      </div>`
  }

  _gridTile(e) {
    const sel = this.selection.has(e.path)
    let boxSz = "w-28 p-2.5"
    let iconHolder = "h-16 w-16"
    if (this.showThumbnails && this.thumbSize === "lg") {
      boxSz = "w-56 p-3"
      iconHolder = "h-48 w-48"
    } else if (this.showThumbnails && this.thumbSize === "md") {
      boxSz = "w-36 p-3"
      iconHolder = "h-28 w-28"
    }
    return `
      <div class="group flex flex-col items-center justify-center gap-1.5 ${boxSz} rounded-lg border cursor-pointer ${sel ? "bg-cyan-500/10 border-cyan-500/30" : "border-transparent hover:bg-surface-active/50 hover:border-border-subtle"}"
           data-path="${e.path}" data-action="click->vps-file-browser#rowClick dblclick->vps-file-browser#openFromRow">
        <div class="flex items-center justify-center ${iconHolder}">${this._icon(e, true)}</div>
        <span class="text-xs text-text-primary text-center truncate w-full" title="${this._esc(e.name)}">${this._esc(e.name)}</span>
      </div>`
  }

  _detailsTable(list) {
    const rows = list.map(e => {
      const sel = this.selection.has(e.path)
      return `
        <tr class="cursor-pointer border-b border-border-subtle/50 last:border-0 ${sel ? "bg-cyan-500/10" : "hover:bg-surface-active/50"}"
            data-path="${e.path}" data-action="click->vps-file-browser#rowClick dblclick->vps-file-browser#openFromRow">
          <td class="px-3 py-1.5"><div class="flex items-center gap-2">${this._icon(e)}<span class="text-sm text-text-primary truncate">${this._esc(e.name)}</span></div></td>
          <td class="px-3 py-1.5 text-xs text-text-muted text-right">${e.type === "directory" ? "—" : this._humanSize(e.size)}</td>
          <td class="px-3 py-1.5 text-xs text-text-muted">${e.modified ? new Date(e.modified).toLocaleString() : "—"}</td>
          <td class="px-3 py-1.5 text-xs text-text-muted font-mono">${(e.permissions & 0o777).toString(8)}</td>
          <td class="px-3 py-1.5"><div class="flex items-center gap-0.5">${this._actions(e)}</div></td>
        </tr>`
    }).join("")
    return `
      <table class="w-full">
        <thead class="sticky top-0 bg-surface-raised z-10 border-b border-border"><tr class="text-left text-xs text-text-muted">
          <th class="px-3 py-1.5 font-medium">Nome</th><th class="px-3 py-1.5 font-medium text-right">Tamanho</th>
          <th class="px-3 py-1.5 font-medium">Modificado</th><th class="px-3 py-1.5 font-medium">Permissões</th><th></th>
        </tr></thead>
        <tbody>${rows}</tbody>
      </table>`
  }

  openFromRow(event) {
    if (event.target.closest("button, a, input")) return
    const path = event.currentTarget.dataset.path
    const entry = this.entries.find(e => e.path === path)
    if (entry) this.open(entry)
  }

  _renderBreadcrumb() {
    const parts = this.path.split("/").filter(Boolean)
    let acc = ""
    const crumbs = [`<button class="px-1.5 py-0.5 rounded hover:bg-surface-active text-text-secondary" data-path="/" data-action="click->vps-file-browser#navigate">/</button>`]
    parts.forEach(p => {
      acc += `/${p}`
      crumbs.push(`<span class="text-text-muted">/</span><button class="px-1.5 py-0.5 rounded hover:bg-surface-active text-text-secondary whitespace-nowrap" data-path="${acc}" data-action="click->vps-file-browser#navigate">${this._esc(p)}</button>`)
    })
    this.breadcrumbTarget.innerHTML = crumbs.join("")
  }

  _renderClipboard() {
    if (!this.clipboard) { this.pasteBarTarget.classList.add("hidden"); return }
    this.pasteBarTarget.classList.remove("hidden")
    const { mode, names } = this.clipboard
    const label = names.length === 1 ? names[0] : `${names.length} itens`
    this.clipNameTarget.textContent = `${mode === "cut" ? "Recortado" : "Copiado"}: ${label}`
  }

  _renderBulkBar() {
    // Grid tiles have no per-item action row (unlike list/details), so this
    // bar is the only way to download from grid mode — show it from 1
    // selected, not just 2+.
    if (!this.selection.size) { this.bulkBarTarget.classList.add("hidden"); return }
    this.bulkBarTarget.classList.remove("hidden")
    this.bulkCountTarget.textContent = this.selection.size === 1 ? "1 selecionado" : `${this.selection.size} selecionados`
  }

  _humanSize(bytes) {
    if (bytes == null) return "—"
    const u = ["B", "KB", "MB", "GB", "TB"]
    let i = 0, n = bytes
    while (n >= 1024 && i < u.length - 1) { n /= 1024; i++ }
    return `${n.toFixed(i ? 1 : 0)} ${u[i]}`
  }

  _esc(s) { return s.replace(/[&<>"]/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c])) }

  _progress(msg) {
    if (msg == null) { this.progressTarget.classList.add("hidden"); return }
    this.progressTarget.classList.remove("hidden")
    this.progressTarget.textContent = msg
  }

  // ── HTTP ────────────────────────────────────────────────────────────────

  _url(action) { return `/vps_hosts/${this.hostIdValue}/files${action ? `/${action}` : ""}` }
  _csrfHeaders() { return { "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content } }

  async _get(action, params = {}) {
    const qs = new URLSearchParams(params).toString()
    const res = await fetch(`${this._url(action)}${qs ? `?${qs}` : ""}`, { headers: { Accept: "application/json" } })
    const body = await res.json()
    if (!res.ok || body.error) throw new Error(body.error || res.statusText)
    return body
  }

  async _post(action, params) {
    const res = await fetch(this._url(action), {
      method: "POST",
      headers: { "Content-Type": "application/json", Accept: "application/json", ...this._csrfHeaders() },
      body: JSON.stringify(params),
    })
    const body = await res.json()
    if (!body.ok) throw new Error(body.error || "Falhou")
    return body
  }

  async _patch(action, params) {
    const res = await fetch(this._url(action), {
      method: "PATCH",
      headers: { "Content-Type": "application/json", Accept: "application/json", ...this._csrfHeaders() },
      body: JSON.stringify(params),
    })
    const body = await res.json()
    if (!body.ok) throw new Error(body.error || "Falhou")
    return body
  }

  async _delete(paths) {
    const res = await fetch(this._url(""), {
      method: "DELETE",
      headers: { "Content-Type": "application/json", Accept: "application/json", ...this._csrfHeaders() },
      body: JSON.stringify({ paths }),
    })
    const body = await res.json()
    if (!body.ok) throw new Error(body.error || "Falhou")
    return body
  }
}
