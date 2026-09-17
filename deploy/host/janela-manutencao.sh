#!/usr/bin/env bash
# Janela de manutenção da lab-01: atualiza Docker + netplan e reinicia a VPS.
# Autorizado pelo Welinton em 2026-09-17 para a madrugada. Roda uma vez (o cron se apaga).
#
# Ordem: confere backup → atualiza → confere serviços → avisa → reinicia.
# Depois do boot, `pos-reboot.sh` (cron @reboot) confere tudo de novo e manda o relatório.
set -uo pipefail
LOG=/var/log/janela-manutencao.log
exec >>"$LOG" 2>&1
echo "=== $(date '+%F %T') início ==="

avisar() { ~/.claude/skills/whatsapp-falar/wa_falar.py --para welinton --texto "$1" >/dev/null 2>&1 || true; }

# 1. Backup recente? Sem backup fresco, não mexe.
IDADE_WAL=$(( ($(date +%s) - $(stat -c %Y /var/log/redhusky-backup.log 2>/dev/null || echo 0)) / 3600 ))
if [ "$IDADE_WAL" -gt 30 ]; then
  avisar "⚠️ Janela de manutenção ABORTADA: o último backup tem ${IDADE_WAL}h (esperado < 30h). Não atualizei nem reiniciei nada."
  echo "abortado: backup velho (${IDADE_WAL}h)"; exit 1
fi

# 2. Docker + netplan
apt-mark unhold docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Options::=--force-confold upgrade
VERSAO=$(docker --version 2>/dev/null)

# 3. Serviços de pé antes de reiniciar a máquina?
sleep 60
FORA=$(docker service ls --format '{{.Name}} {{.Replicas}}' | awk '{split($2,r,"/"); if (r[1]+0 < r[2]+0) print $1}' | tr '\n' ' ')

avisar "🔧 Janela de manutenção: Docker atualizado ($VERSAO).
Serviços fora do ar agora: ${FORA:-nenhum}.
Reiniciando a VPS para subir o kernel novo — volto com o relatório em ~3 min."

echo "reiniciando $(date '+%F %T'), fora: ${FORA:-nenhum}"
sleep 10
systemctl reboot
