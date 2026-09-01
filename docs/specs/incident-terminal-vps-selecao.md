# Incidente — terminal VPS: não dá pra selecionar/copiar, e sessões vazam

**Achado:** v0.9.59 · **Corrigido:** v0.9.60 · **Parcialmente revertido:** v0.9.61

Três sintomas, uma origem: o commit `c2386da` *"prioriza tmux para persistência
com redraw de buffer e reuso de sessão"*.

---

## ⚠️ Leia isto antes de mexer em `shell_command`

A ordem dos wrappers **já foi trocada duas vezes nos dois sentidos**, aqui e no
`redhusky-remote-ssh`. O pêndulo é este:

| Ordem | Seleção com arrasto | Roda do mouse | **Reattach** |
|---|---|---|---|
| **tmux primeiro** (atual) | só com **Shift** | rola o painel | **confiável** |
| dtach primeiro (v0.9.60) | livre | rola o scrollback do xterm | **trava** |
| tmux com `mouse off` | livre | morta | confiável |

**O reattach é o critério que decide.** É pra isso que este terminal existe:
fechar o navegador, voltar depois e continuar de onde parou.

`tmux new-session -A -s NAME` é atômico contra o servidor tmux: duas invocações
concorrentes pro mesmo nome anexam na mesma sessão. `dtach -A SOCKET` não é —
ele cria o socket se não existir, então dois execs SSH disputando o mesmo slot
tentam ser dono do mesmo caminho; o perdedor fica com master órfão e o cliente
anexa num pty que não é o do shell dele. Sintoma: **cursor piscando, nada
responde, sessão perdida** — sem recuperação a não ser abrir outra do lado.

E este terminal corre essa corrida por construção: `#terminal` monta **todos**
os painéis ativos de uma vez, cada um abrindo seu canal, e o `doReconnect()`
abre mais um por cima.

Precisar de Shift pra copiar é irritação. Perder o reattach é perder a sessão.

Se for tentar resolver os dois de uma vez, o caminho **não** é reordenar: é um
botão na toolbar que alterna `tmux set -g mouse on|off` na sessão viva. Aí a
pessoa escolhe o modo na hora, sem que ninguém pague o preço fixo.

---

## 1. Seleção some no meio do arrasto

**Sintoma.** Arrastar pra selecionar texto destaca e imediatamente
"desseleciona"; copiar (auto-copy no mouseup, Ctrl+C, botão) não traz nada. O
terminal do `redhusky-remote-ssh` faz certo no mesmo host.

**Causa.** `VpsSshService#shell_command` tinha o tmux como **primeiro** branch
incondicional, iniciado com `set -g mouse on`. Com mouse tracking (modo 1002)
ligado, cada movimento do mouse durante o arrasto vira um report pro tmux, o
tmux redesenha, e o redraw apaga a seleção do xterm. Nunca dá pra terminar a
seleção. O `\x1b[?1000l…1002l…` que o `vps_terminal_controller.js` escreve no
`connected` não resolve: é escrita local, o tmux religa o modo no redraw
seguinte.

**Tentativa (v0.9.60).** Ordem invertida para **dtach > abduco > tmux**. Fez o
que prometia: seleção nativa livre, sem Shift, e — ao contrário do que a gente
temia — a roda do mouse continuou rolando normal, pelo scrollback do xterm
(10.000 linhas, `vps_terminal_controller.js`). Por algumas horas pareceu ganho
puro.

**Por que foi revertida (v0.9.61).** O custo real não era a rolagem, era o
**reattach**. Voltar na sessão dava cursor piscando e nada mais — não reatava.
Evidência no host durante o incidente: **dois masters `dtach` no mesmo socket**,
para os dois slots em uso, com horários de criação diferentes — a corrida
descrita acima. O `c2386da` já avisava na primeira linha — *"persistência com
redraw de buffer"* — e a frase foi lida como se fosse só sobre scroll.

**Estado atual.** Volta pra **tmux > dtach > abduco**, tmux incondicional com
`set -g mouse on`. Selecionar exige **Shift** — e agora a toolbar diz isso, em
`_pane.html.erb`, que é o que faltava desde o começo: o Shift sempre funcionou,
só não estava escrito em lugar nenhum.

> **Precisão sobre o `redhusky-remote-ssh`.** Aquele repo (`docs/incident-fixes.md`
> #8) rejeitou o `mouse off`, não o dtach — lá o dtach é o padrão e funciona bem,
> porque o uso é shell interativo curto, não sessão longa pra reatar. Contexto
> diferente, conclusão diferente. Não importe a decisão de lá pra cá sem olhar
> qual dos dois problemas você está resolvendo.

## 2. Não dá pra abrir uma segunda sessão no mesmo host

**Causa.** `VpsTerminalSessionsController#create` sempre reusava a sessão mais
recente do host e redirecionava — não havia caminho pra criar outra.

**Correção.** O reuso continua sendo o padrão (você volta pra onde parou), mas
`?new=1` força uma sessão nova, que o model coloca no menor slot livre e
portanto com shell próprio. Botão `+` na barra de abas.

## 3. Shells órfãos acumulando no host

**Sintoma.** `tmux ls` no host mostrando sessões `vps_<uuid>_sN` que a UI não
lista e ninguém alcança.

**Causa.** `destroy` apagava a linha no banco e derrubava a thread SSH, mas
nunca matava o shell remoto. Sem a linha, nada mais conhece o nome/socket
daquele slot — o shell fica destacado pra sempre. A própria confirmação dizia
"o shell continua vivo no host".

**Correção.** `VpsSshService#kill_remote_shell` (SSH one-shot: `tmux
kill-session` + `abduco -k` + `pkill` do dtach + remove o socket), chamado no
`destroy`. Best-effort: host inalcançável não bloqueia apagar a linha. A
confirmação agora diz a verdade — o shell remoto é destruído.

## Verificação

`platform-rails/test/services/vps_ssh_service_shell_command_test.rb` roda o
snippet gerado num `/bin/sh` real com tmux/dtach falsos no PATH e afirma a
escolha de cada branch. Falha se a ordem for revertida.
