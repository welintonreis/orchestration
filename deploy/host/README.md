# Coletores do host

A tela de Segurança lê `/srv/redhusky/security/state.json`, escrito por estes
scripts via cron do root (`*/5` o de segurança, `*/15` o de diff de container).
Eles rodam **no host**, não em container: leem `journalctl`, `/proc/1/net/tcp` e
o socket do Docker.

Ficavam só em `/usr/local/bin/` — fora do git. Um bug neles é invisível no
histórico e some se a máquina sumir. Ao alterar, copie para cá e faça commit.

```bash
sudo cp deploy/host/security-collect.sh /usr/local/bin/
```

## O bug de 2026-09-09 — monitor que só funciona quando há problema

`grep` sem match sai 1; com `set -o pipefail` e `set -e`, o coletor **morria
exatamente quando não havia ataque nenhum**. O `state.json` congelava no último
dia com tentativa, e a tela seguia exibindo aquele ataque como se fosse das
últimas 24h. Ficou 10 dias mostrando uma tentativa vinda de Lima, Peru
(2026-08-31), muito depois de os ataques terem cessado.

Falha pior que a ausência de monitor: dá alarme falso e esconde o estado real.

Ao mexer aqui, teste os **dois** lados — com ataque plantado e com entrada
vazia:

```bash
printf 'Failed password for root from 203.0.113.7 port 22 ssh2\n' \
  | grep -E "Failed password|Invalid user" | grep -oE 'from [0-9.]+' # deve achar
printf '' | grep -E "Failed password" ; echo "exit=$?"                # deve ser 1
```
