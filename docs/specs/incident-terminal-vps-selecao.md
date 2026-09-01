# Incidente — terminal VPS: não dá pra selecionar/copiar, e sessões vazam

**Achado:** v0.9.59 · **Corrigido:** v0.9.60

Três sintomas, uma origem: o commit `c2386da` *"prioriza tmux para persistência
com redraw de buffer e reuso de sessão"*.

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

**Correção.** Ordem de preferência invertida para **dtach > abduco > tmux**.
dtach é pty transparente, não captura mouse — a seleção nativa do xterm volta a
funcionar. O tmux continua ganhando quando **já existe** uma sessão com o nome
do slot no host: instalar dtach não pode órfãozar o workspace tmux onde a
pessoa já mora.

**Trade-off aceito.** Sem tmux, a roda do mouse rola o scrollback do xterm
(10.000 linhas, `vps_terminal_controller.js`) em vez do copy-mode do pane. É o
comportamento do `redhusky-remote-ssh`, e é o histórico real da saída.

> **Não reverter pra tmux-primeiro.** O `redhusky-remote-ssh` já passou por esse
> ciclo (ver `docs/incident-fixes.md` #8 daquele repo): tentaram manter tmux com
> `mouse off`, o que matou a rolagem porque o tmux repinta a tela inteira e o
> scrollback do xterm fica vazio. Sem tmux o problema não existe.

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
