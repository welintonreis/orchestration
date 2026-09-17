// Diálogos com a cara do sistema no lugar de confirm()/prompt()/alert() do navegador.
//
// O modal nasce em JS a cada chamada, e não no layout: o gerenciador de arquivos também abre no
// layout `embed`, que não tinha o #confirm-modal — lá o Turbo caía no confirm() nativo.
//
//   if (!(await confirmDialog("Apagar X?"))) return
//   const nome = await promptDialog("Nome da nova pasta:")      // null se cancelar
//   await alertDialog("Não foi possível apagar.", { detalhe: e.message })
//   Mensagem aceita **negrito** pro nome do arquivo ou a quantidade.
//
// O estilo mora aqui (CSS injetado uma vez) e usa os tokens do tema (--brand, --surface-raised…):
// medidas exatas de espaçamento, sombra e animação que as classes utilitárias não expressam bem,
// e que precisam valer nos temas redhusky/ice, claro e escuro.

const CSS = `
.rhd-raiz { position: fixed; inset: 0; z-index: 10000; display: flex; align-items: center; justify-content: center; padding: 16px; }
.rhd-fundo { position: absolute; inset: 0; background: rgba(0,0,0,.5); backdrop-filter: blur(4px); -webkit-backdrop-filter: blur(4px); animation: rhd-fade 120ms ease-out; }
.rhd-caixa { position: relative; width: 400px; max-width: calc(100vw - 32px); background: var(--surface-raised, #fff); color: var(--text-primary, #111827);
  border-radius: 12px; padding: 24px; box-shadow: 0 20px 40px -12px rgba(0,0,0,.35); animation: rhd-entra 160ms cubic-bezier(.16,1,.3,1); box-sizing: border-box; }
:where(.dark) .rhd-caixa { background: #1C2128; box-shadow: none; border: 1px solid rgba(255,255,255,.08); }
.rhd-topo { display: flex; gap: 16px; align-items: flex-start; }
.rhd-bola { flex: none; width: 40px; height: 40px; border-radius: 9999px; display: grid; place-items: center; }
.rhd-bola svg { width: 20px; height: 20px; }
.rhd-bola.perigo { background: #FEE2E2; color: #DC2626; }
:where(.dark) .rhd-bola.perigo { background: rgba(239,68,68,.16); color: #F87171; }
.rhd-bola.neutro { background: color-mix(in srgb, var(--brand, #E84518) 12%, transparent); color: var(--brand, #E84518); }
:where(.dark) .rhd-bola.neutro { background: color-mix(in srgb, var(--brand, #F97316) 16%, transparent); color: color-mix(in srgb, var(--brand, #F97316) 70%, white); }
.rhd-texto { flex: 1; min-width: 0; }
.rhd-titulo { font-size: 16px; font-weight: 600; line-height: 1.4; margin: 0; }
.rhd-msg strong { color: var(--text-primary, #111827); font-weight: 600; }
:where(.dark) .rhd-msg strong { color: #F3F4F6; }
.rhd-detalhe { margin: 8px 0 0; font: 13px/1.45 ui-monospace, SFMono-Regular, Menlo, monospace; color: #6B7280; overflow-wrap: anywhere; }
:where(.dark) .rhd-detalhe { color: #8B949E; }
.rhd-msg { font-size: 14px; line-height: 1.5; color: #4B5563; margin: 6px 0 0; overflow-wrap: anywhere; white-space: pre-line; }
:where(.dark) .rhd-msg { color: #A1A1AA; }
.rhd-rotulo { display: block; font-size: 13px; font-weight: 500; color: #374151; margin: 8px 0 8px; }
:where(.dark) .rhd-rotulo { color: #D1D5DB; }
.rhd-campo { width: 100%; height: 40px; padding: 0 12px; font-size: 14px; border-radius: 8px; border: 1px solid #D1D5DB;
  background: var(--surface-raised, #fff); color: inherit; outline: none; transition: border-color 120ms, box-shadow 120ms; box-sizing: border-box; }
:where(.dark) .rhd-campo { border-color: #374151; background: #161B22; }
.rhd-campo:focus { border-color: var(--brand, #E84518); box-shadow: 0 0 0 3px color-mix(in srgb, var(--brand, #E84518) 25%, transparent); }
:where(.dark) .rhd-campo:focus { box-shadow: 0 0 0 3px color-mix(in srgb, var(--brand, #F97316) 35%, transparent); }
.rhd-botoes { display: flex; justify-content: flex-end; gap: 8px; margin-top: 20px; }
.rhd-btn { min-width: 88px; height: 36px; padding: 0 16px; border-radius: 8px; font-size: 14px; font-weight: 500; cursor: pointer; border: 1px solid transparent;
  outline: none; transition: background-color 120ms, box-shadow 120ms, filter 120ms; }
.rhd-btn.secundario { background: transparent; color: #374151; border-color: #D1D5DB; }
.rhd-btn.secundario:hover { background: #F3F4F6; }
:where(.dark) .rhd-btn.secundario { color: #D1D5DB; border-color: #374151; }
:where(.dark) .rhd-btn.secundario:hover { background: rgba(255,255,255,.06); }
.rhd-btn.primario { --cor: var(--brand, #E84518); background: var(--cor); color: #fff; }
.rhd-btn.perigo { --cor: #DC2626; background: var(--cor); color: #fff; }
:where(.dark) .rhd-btn.perigo { --cor: #EF4444; }
.rhd-btn.neutro { --cor: #1E293B; background: var(--cor); color: #fff; }
:where(.dark) .rhd-btn.neutro { --cor: #F1F5F9; color: #0F172A; }
.rhd-btn.primario:hover, .rhd-btn.perigo:hover, .rhd-btn.neutro:hover { filter: brightness(1.08); }
.rhd-btn:focus-visible { box-shadow: 0 0 0 2px var(--surface-raised, #fff), 0 0 0 4px color-mix(in srgb, var(--cor, #6B7280) 50%, transparent); }
:where(.dark) .rhd-btn:focus-visible { box-shadow: 0 0 0 2px #1C2128, 0 0 0 4px color-mix(in srgb, var(--cor, #9CA3AF) 50%, transparent); }
@keyframes rhd-fade { from { opacity: 0 } to { opacity: 1 } }
@keyframes rhd-entra { from { opacity: 0; transform: scale(.96) } to { opacity: 1; transform: scale(1) } }
@media (prefers-reduced-motion: reduce) { .rhd-fundo, .rhd-caixa { animation: none } }
`

const ICONES = {
  perigo: `<path stroke-linecap="round" stroke-linejoin="round" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"/>`,
  erro:   `<circle cx="12" cy="12" r="9"/><path stroke-linecap="round" d="M12 8v4m0 4h.01"/>`,
  editar: `<path stroke-linecap="round" stroke-linejoin="round" d="M16.862 4.487l1.687-1.688a1.875 1.875 0 112.652 2.652L6.832 19.82a4.5 4.5 0 01-1.897 1.13l-2.685.8.8-2.685a4.5 4.5 0 011.13-1.897L16.863 4.487z"/>`,
}

function injetarEstilo() {
  if (document.getElementById("rhd-estilo")) return
  const s = document.createElement("style")
  s.id = "rhd-estilo"
  s.textContent = CSS
  document.head.appendChild(s)
}

// Mensagem aceita **trecho** em negrito (nome de arquivo, quantidade) — o resto é texto puro.
function comDestaque(t) {
  return escapar(t).replace(/\*\*(.+?)\*\*/g, "<strong>$1</strong>")
}

function escapar(t) {
  const d = document.createElement("div")
  d.textContent = t ?? ""
  return d.innerHTML
}

// icone: perigo | erro | editar · bola: perigo | neutro · botao: perigo | primario | neutro
function abrir({ icone, bola, botao, titulo, mensagem, detalhe = null, okLabel, cancelar = true, campo = null }) {
  injetarEstilo()
  return new Promise((resolve) => {
    const anterior = document.activeElement
    const raiz = document.createElement("div")
    raiz.className = "rhd-raiz"
    raiz.setAttribute("role", "dialog")
    raiz.setAttribute("aria-modal", "true")
    raiz.setAttribute("aria-labelledby", "rhd-titulo")
    raiz.innerHTML = `
      <div class="rhd-fundo" data-fundo></div>
      <div class="rhd-caixa">
        <div class="rhd-topo">
          <div class="rhd-bola ${bola}">
            <svg fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">${ICONES[icone]}</svg>
          </div>
          <div class="rhd-texto">
            <h3 class="rhd-titulo" id="rhd-titulo">${escapar(titulo)}</h3>
            ${campo
              ? `<label class="rhd-rotulo" for="rhd-campo">${escapar(mensagem.replace(/:\s*$/, ""))}</label>
                 <input id="rhd-campo" class="rhd-campo" data-campo type="text" autocomplete="off" spellcheck="false"
                        value="${escapar(campo.valor)}" placeholder="${escapar(campo.placeholder)}">`
              : `<p class="rhd-msg">${comDestaque(mensagem)}</p>${detalhe ? `<p class="rhd-detalhe">${escapar(detalhe)}</p>` : ""}`}
          </div>
        </div>
        <div class="rhd-botoes">
          ${cancelar ? `<button type="button" class="rhd-btn secundario" data-cancelar>Cancelar</button>` : ""}
          <button type="button" class="rhd-btn ${botao}" data-ok>${escapar(okLabel)}</button>
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
    } else {
      // Enter confirma; o anel de foco (:focus-visible) só aparece quando a pessoa navega por Tab.
      raiz.querySelector("[data-ok]").focus({ focusVisible: false })
    }
  })
}

export function confirmDialog(mensagem, { titulo = "Confirmar ação", ok = "Confirmar", perigo = true } = {}) {
  return perigo
    ? abrir({ icone: "perigo", bola: "perigo", botao: "perigo", titulo, mensagem, okLabel: ok })
    : abrir({ icone: "editar", bola: "neutro", botao: "primario", titulo, mensagem, okLabel: ok })
}

export function promptDialog(mensagem, valor = "", { titulo = "Informe", ok = "Salvar", placeholder = "", semExtensao = false } = {}) {
  return abrir({ icone: "editar", bola: "neutro", botao: "primario", titulo, mensagem, okLabel: ok, campo: { valor, placeholder, semExtensao } })
}

// detalhe: a mensagem técnica (e.message), em letra menor embaixo da frase legível.
export function alertDialog(mensagem, { titulo = "Algo deu errado", detalhe = null } = {}) {
  return abrir({ icone: "erro", bola: "perigo", botao: "neutro", titulo, mensagem, detalhe, okLabel: "OK", cancelar: false })
}
