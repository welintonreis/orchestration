#!/usr/bin/env bash
# Limpeza de imagens/containers da lab-01. Roda no HOST (cron), não em container.
#
# Por que existe: cada deploy gera uma tag nova e só 5 dos ~15 deploy-prod.sh limpam
# atrás de si (cnroute tinha 11 tags, orchestration 6). Em vez de repetir a limpeza em
# cada script, um lugar só cuida de todos os projetos.
#
# Regra: por repositório, mantém as MANTER tags mais novas (padrão 2: a de produção e a
# anterior, pra rollback) e tudo que estiver EM USO por serviço do Swarm ou container.
# Remove o resto. Containers parados há mais de 24h também saem.
#
#   limpar-imagens.sh            # dry-run: só mostra o que faria
#   limpar-imagens.sh --aplicar  # remove de verdade
set -uo pipefail

MANTER=${MANTER:-2}
APLICAR=0; [ "${1:-}" = "--aplicar" ] && APLICAR=1
rodar() { if [ "$APLICAR" = 1 ]; then "$@"; else echo "  [dry-run] $*"; fi; }

# --- imagens em uso: serviços do Swarm (inclusive as paradas de update) e containers ----
em_uso=$(mktemp)
{
  docker service ls -q | xargs -r docker service inspect \
    --format '{{.Spec.TaskTemplate.ContainerSpec.Image}}' 2>/dev/null
  docker ps -a --format '{{.Image}}'
} | sed 's/@sha256:.*//' | sort -u > "$em_uso"

removidas=0
for repo in $(docker images --format '{{.Repository}}' | grep -v '^<none>$' | sort -u); do
  # ordem do docker images é por data de criação (mais nova primeiro)
  mapfile -t tags < <(docker images "$repo" --format '{{.Repository}}:{{.Tag}}' | grep -v ':<none>$')
  [ "${#tags[@]}" -le "$MANTER" ] && continue
  echo "$repo: ${#tags[@]} tags"
  for tag in "${tags[@]:$MANTER}"; do
    if grep -qxF "$tag" "$em_uso"; then echo "  mantém (em uso) $tag"; continue; fi
    echo "  remove $tag"
    rodar docker rmi "$tag" >/dev/null 2>&1
    removidas=$((removidas + 1))
  done
done
rm -f "$em_uso"

# --- containers parados há mais de 24h ---------------------------------------------------
parados=$(docker ps -a --filter status=exited --filter status=created -q | wc -l)
[ "$parados" -gt 0 ] && { echo "containers parados: $parados"; rodar docker container prune -f --filter until=24h; }

# --- camadas órfãs e cache de build ------------------------------------------------------
rodar docker image prune -f
rodar docker builder prune -af --reserved-space 10GB

echo "imagens marcadas para remoção: $removidas (aplicar=$APLICAR, manter=$MANTER por repo)"
docker system df | tail -n +2
