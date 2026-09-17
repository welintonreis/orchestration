#!/usr/bin/env bash
# Confere a lab-01 depois de um boot e manda o relatório pro WhatsApp do Welinton.
# Instalado como cron @reboot. Espera o Swarm convergir antes de julgar.
set -uo pipefail
LOG=/var/log/pos-reboot.log
exec >>"$LOG" 2>&1
echo "=== $(date '+%F %T') boot: kernel $(uname -r) ==="

# espera até 10 min o Swarm convergir
for _ in $(seq 1 60); do
  sleep 10
  docker info >/dev/null 2>&1 || continue
  FORA=$(docker service ls --format '{{.Name}} {{.Replicas}}' 2>/dev/null | awk '{split($2,r,"/"); if (r[1]+0 < r[2]+0) print $1}' | tr '\n' ' ')
  [ -z "$FORA" ] && break
done

TOT=$(docker service ls -q 2>/dev/null | wc -l)
SAUD=$(docker ps --format '{{.Status}}' | grep -c healthy)
DOENTES=$(docker ps --format '{{.Names}} {{.Status}}' | grep unhealthy | cut -d. -f1 | tr '\n' ' ')
WA=$(docker exec "$(docker ps -q -f name=evolution_evolution-api | head -1)" node -e '
  fetch("http://127.0.0.1:8080/instance/fetchInstances",{headers:{apikey:process.env.AUTHENTICATION_API_KEY}})
   .then(r=>r.json()).then(j=>{const a=Array.isArray(j)?j:(j.instances||[]);
   console.log(a.map(i=>{const x=i.instance||i; return (x.instanceName||x.name)+"="+(x.connectionStatus||x.state);}).join(", "));})' 2>/dev/null)

MSG="✅ VPS reiniciada e de pé.
Kernel: $(uname -r)
Docker: $(docker --version | cut -d, -f1)
Serviços: $TOT | containers saudáveis: $SAUD
Fora do ar: ${FORA:-nenhum}
Doentes: ${DOENTES:-nenhum}
WhatsApp: ${WA:-não consegui consultar}"
~/.claude/skills/whatsapp-falar/wa_falar.py --para welinton --texto "$MSG" >/dev/null 2>&1 || echo "falhou o aviso"
echo "$MSG"
