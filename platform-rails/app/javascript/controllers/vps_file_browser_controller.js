import { Controller } from "@hotwired/stimulus"

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
    "pasteBar", "clipName", "bulkBar", "bulkCount",
    "previewModal", "previewTitle", "previewBody", "previewDownloadBtn",
  ]
  static values = { hostId: String }

  connect() {
    this.path = "/"
    this.entries = []
    this.filterText = ""
    this.showHidden = false
    this.selection = new Set()
    this.cursor = -1
    this.clipboard = null // { mode: "copy"|"cut", path, name }
    this.viewMode = localStorage.getItem("tb:vpsfiles:view") || "list"
    this.load()
  }

  // ── navigation ──────────────────────────────────────────────────────────

  async load(path = this.path) {
    this.path = path
    this.selection.clear()
    this._progress("Carregando…")
    try {
      const res = await this._get("", { path })
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
    if (entry.type === "directory") this.load(entry.path)
    else this.openPreview(entry)
  }

  // ── toolbar ─────────────────────────────────────────────────────────────

  setFilter(event) { this.filterText = event.target.value.toLowerCase(); this._render() }

  toggleHidden() {
    this.showHidden = !this.showHidden
    this.hiddenBtnTarget.classList.toggle("text-cyan-500", this.showHidden)
    this._render()
  }

  setViewMode(event) {
    this.viewMode = event.params.mode
    localStorage.setItem("tb:vpsfiles:view", this.viewMode)
    this._render()
  }

  async newFolder() {
    const name = prompt("Nome da nova pasta:")
    if (!name) return
    this._progress("Criando pasta…")
    try { await this._post("mkdir", { path: this.path, name }); await this.load() }
    catch (e) { alert(`Falha: ${e.message}`) }
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
    } catch (e) { alert(`Upload falhou: ${e.message}`) }
    finally { this._progress(null); event.target.value = "" }
  }

  // ── selection ───────────────────────────────────────────────────────────

  rowClick(event) {
    const path = event.currentTarget.dataset.path
    const idx  = this.entries.findIndex(e => e.path === path)
    if (event.shiftKey && this.cursor >= 0) {
      const [a, b] = [this.cursor, idx].sort((x, y) => x - y)
      this.selection = new Set(this.entries.slice(a, b + 1).map(e => e.path))
    } else if (event.ctrlKey || event.metaKey) {
      this.selection.has(path) ? this.selection.delete(path) : this.selection.add(path)
    } else {
      this.selection = new Set([path])
    }
    this.cursor = idx
    this._render()
  }

  clearSelection() { this.selection.clear(); this._render() }

  keydown(event) {
    if (!this.entries.length) return
    const visible = this._visibleEntries()
    if (event.key === "ArrowDown" || event.key === "ArrowUp") {
      event.preventDefault()
      this.cursor = Math.min(Math.max((event.key === "ArrowDown" ? this.cursor + 1 : this.cursor - 1), 0), visible.length - 1)
      this.selection = new Set([visible[this.cursor]?.path].filter(Boolean))
      this._render()
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
      this._render()
    }
  }

  // ── file ops ────────────────────────────────────────────────────────────

  download(event) {
    const path = event.currentTarget.dataset.path
    window.location = `${this._url("download")}?path=${encodeURIComponent(path)}`
  }

  downloadArchive(event) {
    const path = event.currentTarget.dataset.path
    window.location = `${this._url("archive")}?path=${encodeURIComponent(path)}`
  }

  downloadSelectionArchive() {
    if (!this.selection.size) return
    const qs = [...this.selection].map(p => `paths[]=${encodeURIComponent(p)}`).join("&")
    window.location = `${this._url("archive")}?${qs}`
  }

  async copyPath(event) {
    try { await navigator.clipboard.writeText(event.currentTarget.dataset.path) } catch {}
  }

  cut(event)  { this.clipboard = { mode: "cut",  path: event.currentTarget.dataset.path, name: event.currentTarget.dataset.name }; this._renderClipboard() }
  copy(event) { this.clipboard = { mode: "copy", path: event.currentTarget.dataset.path, name: event.currentTarget.dataset.name }; this._renderClipboard() }
  clearClipboard() { this.clipboard = null; this._renderClipboard() }

  async paste() {
    if (!this.clipboard) return
    const { mode, path } = this.clipboard
    this._progress(mode === "cut" ? "Movendo…" : "Copiando…")
    try {
      await this._post(mode === "cut" ? "move" : "copy", { path, dest: this.path })
      this.clipboard = null
      this._renderClipboard()
      await this.load()
    } catch (e) { alert(`Falha: ${e.message}`) }
    finally { this._progress(null) }
  }

  async rename(event) {
    const path = event.currentTarget.dataset.path
    const name = prompt("Novo nome:", event.currentTarget.dataset.name)
    if (!name || name === event.currentTarget.dataset.name) return
    try { await this._patch("rename", { path, name }); await this.load() }
    catch (e) { alert(`Falha: ${e.message}`) }
  }

  async destroy(event) {
    const path = event.currentTarget.dataset.path
    if (!confirm(`Apagar "${event.currentTarget.dataset.name}"?`)) return
    this._progress("Apagando…")
    try { await this._delete([path]); await this.load() }
    catch (e) { alert(`Falha: ${e.message}`) }
    finally { this._progress(null) }
  }

  async bulkDelete() {
    if (!this.selection.size) return
    if (!confirm(`Apagar ${this.selection.size} item(ns)?`)) return
    this._progress("Apagando…")
    try { await this._delete([...this.selection]); await this.load() }
    catch (e) { alert(`Falha: ${e.message}`) }
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
    if (!list.length) {
      this.listTarget.innerHTML = `<div class="py-10 text-center text-sm text-text-muted">Pasta vazia</div>`
    } else if (this.viewMode === "grid") {
      this.listTarget.innerHTML = `<div class="flex flex-wrap gap-1 p-2">${list.map(e => this._gridTile(e)).join("")}</div>`
    } else if (this.viewMode === "details") {
      this.listTarget.innerHTML = this._detailsTable(list)
    } else {
      this.listTarget.innerHTML = list.map(e => this._listRow(e)).join("")
    }
    this._renderBulkBar()
  }

  _icon(entry) {
    if (entry.type === "directory") {
      return `<svg class="w-4 h-4 text-cyan-500 shrink-0" fill="currentColor" viewBox="0 0 24 24"><path d="M10 4H4a2 2 0 00-2 2v12a2 2 0 002 2h16a2 2 0 002-2V8a2 2 0 00-2-2h-8l-2-2z"/></svg>`
    }
    return `<svg class="w-4 h-4 text-text-muted shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M7 3h7l5 5v13a1 1 0 01-1 1H7a1 1 0 01-1-1V4a1 1 0 011-1z"/><path stroke-linecap="round" stroke-linejoin="round" d="M14 3v5h5"/></svg>`
  }

  _actions(e) {
    return `
      <button data-action="click->vps-file-browser#copyPath" data-path="${e.path}" title="Copiar caminho" class="p-1 text-text-muted hover:text-text-primary">
        <svg class="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><rect x="9" y="9" width="11" height="11" rx="1"/><path d="M5 15V5a2 2 0 012-2h10"/></svg>
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
    return `
      <div class="group flex flex-col items-center gap-1 w-24 p-2 rounded-lg cursor-pointer ${sel ? "bg-cyan-500/10" : "hover:bg-surface-active/50"}"
           data-path="${e.path}" data-action="click->vps-file-browser#rowClick dblclick->vps-file-browser#openFromRow">
        <div class="scale-[2]">${this._icon(e)}</div>
        <span class="text-xs text-text-primary text-center truncate w-full mt-2" title="${this._esc(e.name)}">${this._esc(e.name)}</span>
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
        <thead><tr class="text-left text-xs text-text-muted border-b border-border">
          <th class="px-3 py-1.5 font-medium">Nome</th><th class="px-3 py-1.5 font-medium text-right">Tamanho</th>
          <th class="px-3 py-1.5 font-medium">Modificado</th><th class="px-3 py-1.5 font-medium">Permissões</th><th></th>
        </tr></thead>
        <tbody>${rows}</tbody>
      </table>`
  }

  openFromRow(event) {
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
    this.clipNameTarget.textContent = `${this.clipboard.mode === "cut" ? "Recortado" : "Copiado"}: ${this.clipboard.name}`
  }

  _renderBulkBar() {
    if (this.selection.size < 2) { this.bulkBarTarget.classList.add("hidden"); return }
    this.bulkBarTarget.classList.remove("hidden")
    this.bulkCountTarget.textContent = `${this.selection.size} selecionados`
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
