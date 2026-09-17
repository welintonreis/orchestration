// Diálogos com a cara do sistema no lugar de confirm()/prompt()/alert() do navegador.
//
// O modal nasce em JS a cada chamada, e não no layout: o gerenciador de arquivos também abre no
// layout `embed`, que não tinha o #confirm-modal — lá o Turbo caía no confirm() nativo.
//
//   if (!(await confirmDialog("Apagar X?"))) return
//   const nome = await promptDialog("Nome da nova pasta:")      // null se cancelar
//   await alertDialog(`Falha: ${e.message}`)

const ICONES = {
  perigo: `<path stroke-linecap="round" stroke-linejoin="round" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"/>`,
  editar: `<path stroke-linecap="round" stroke-linejoin="round" d="M16.862 4.487l1.687-1.688a1.875 1.875 0 112.652 2.652L6.832 19.82a4.5 4.5 0 01-1.897 1.13l-2.685.8.8-2.685a4.5 4.5 0 011.13-1.897L16.863 4.487z"/>`,
  info: `<path stroke-linecap="round" stroke-linejoin="round" d="M11.25 11.25l.041-.02a.75.75 0 011.063.852l-.708 2.836a.75.75 0 001.063.853l.041-.021M21 12a9 9 0 11-18 0 9 9 0 0118 0zm-9-3.75h.008v.008H12V8.25z"/>`,
}
const TONS = {
  perigo: { bola: "bg-red-100 dark:bg-red-900/40 border-red-300 dark:border-red-800/60", icone: "text-red-600 dark:text-red-400", ok: "bg-red-600 hover:bg-red-500 text-white" },
  editar: { bola: "bg-surface-inset border-border-subtle", icone: "text-text-secondary", ok: "bg-brand hover:opacity-90 text-white" },
  info:   { bola: "bg-surface-inset border-border-subtle", icone: "text-text-secondary", ok: "bg-surface-active hover:bg-surface-inset text-text-primary border border-border-subtle" },
}

function escapar(t) {
  const d = document.createElement("div")
  d.textContent = t ?? ""
  return d.innerHTML
}

function abrir({ tipo, titulo, mensagem, okLabel, cancelar = true, campo = null }) {
  return new Promise((resolve) => {
    const tom = TONS[tipo]
    const anterior = document.activeElement
    const raiz = document.createElement("div")
    raiz.className = "fixed inset-0 z-[10000] flex items-center justify-center p-4"
    raiz.setAttribute("role", "dialog")
    raiz.setAttribute("aria-modal", "true")
    raiz.innerHTML = `
      <div data-fundo class="absolute inset-0 bg-black/70 backdrop-blur-sm"></div>
      <div class="relative bg-surface-raised border border-border-subtle rounded-2xl shadow-2xl w-full max-w-sm">
        <div class="px-6 pt-6 pb-2 flex items-start gap-4">
          <div class="flex-shrink-0 w-10 h-10 rounded-full border flex items-center justify-center ${tom.bola}">
            <svg class="w-5 h-5 ${tom.icone}" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">${ICONES[tipo]}</svg>
          </div>
          <div class="flex-1 min-w-0">
            <h3 class="text-base font-semibold text-text-primary">${escapar(titulo)}</h3>
            <p class="text-sm text-text-secondary mt-1 break-words whitespace-pre-line">${escapar(mensagem)}</p>
            ${campo ? `<input data-campo type="text" autocomplete="off" spellcheck="false"
                 class="mt-3 w-full px-3 py-2 text-sm rounded-lg bg-surface-inset border border-border-subtle text-text-primary focus:outline-none focus:ring-2 focus:ring-brand"
                 value="${escapar(campo.valor)}" placeholder="${escapar(campo.placeholder)}">` : ""}
          </div>
        </div>
        <div class="px-6 py-4 flex items-center justify-end gap-3">
          ${cancelar ? `<button type="button" data-cancelar class="px-4 py-2 text-sm font-medium text-text-secondary hover:text-text-primary bg-surface-inset hover:bg-surface-active rounded-lg border border-border-subtle transition-colors">Cancelar</button>` : ""}
          <button type="button" data-ok class="px-4 py-2 text-sm font-medium rounded-lg transition-colors ${tom.ok}">${escapar(okLabel)}</button>
        </div>
      </div>`

    const input = raiz.querySelector("[data-campo]")
    const fechar = (valor) => {
      document.removeEventListener("keydown", teclas, true)
      raiz.remove()
      anterior?.focus?.()
      resolve(valor)
    }
    const confirmar = () => fechar(campo ? input.value.trim() || null : true)
    const desistir = () => fechar(campo ? null : false)
    const teclas = (e) => {
      if (e.key === "Escape") { e.preventDefault(); e.stopPropagation(); desistir() }
      else if (e.key === "Enter") { e.preventDefault(); e.stopPropagation(); confirmar() }
      else if (e.key === "Tab") {
        // foco preso no diálogo
        const focaveis = [...raiz.querySelectorAll("input, button")]
        const i = focaveis.indexOf(document.activeElement)
        const prox = focaveis[(i + (e.shiftKey ? -1 : 1) + focaveis.length) % focaveis.length]
        e.preventDefault(); prox.focus()
      }
    }

    raiz.querySelector("[data-ok]").addEventListener("click", confirmar)
    raiz.querySelector("[data-cancelar]")?.addEventListener("click", desistir)
    raiz.querySelector("[data-fundo]").addEventListener("click", desistir)
    document.addEventListener("keydown", teclas, true)
    document.body.appendChild(raiz)
    if (input) {
      input.focus()
      // Renomear arquivo: seleciona só o nome, sem a extensão — digitar não apaga o ".tar.gz".
      const ponto = campo.semExtensao ? input.value.indexOf(".", 1) : -1
      input.setSelectionRange(0, ponto > 0 ? ponto : input.value.length)
    } else raiz.querySelector("[data-ok]").focus()
  })
}

export function confirmDialog(mensagem, { titulo = "Confirmar ação", ok = "Confirmar", perigo = true } = {}) {
  return abrir({ tipo: perigo ? "perigo" : "info", titulo, mensagem, okLabel: ok })
}

export function promptDialog(mensagem, valor = "", { titulo = "Informe", ok = "Salvar", placeholder = "", semExtensao = false } = {}) {
  return abrir({ tipo: "editar", titulo, mensagem, okLabel: ok, campo: { valor, placeholder, semExtensao } })
}

export function alertDialog(mensagem, { titulo = "Algo deu errado" } = {}) {
  return abrir({ tipo: "info", titulo, mensagem, okLabel: "OK", cancelar: false })
}
