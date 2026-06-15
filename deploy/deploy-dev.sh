#!/usr/bin/env bash
# deploy-dev.sh — build + push + deploy dev stack.
# Uso: bash deploy/deploy-dev.sh [tag]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO="registry.gitlab.redhusky.com.br/redhusk/orchestration"
TAG="${1:-dev}"
IMAGE="${REPO}:${TAG}"
STACK="orchestration-dev"

echo "==> Building Rails image: ${IMAGE}"
docker build \
  --platform linux/amd64 \
  -t "${IMAGE}" \
  "$ROOT/platform-rails/"

echo "==> Pushing to registry"
docker push "${IMAGE}"

echo "==> Deploying stack ${STACK}"
IMAGE="${IMAGE}" \
RAILS_MASTER_KEY="$(cat "$ROOT/platform-rails/config/master.key" 2>/dev/null || echo "${RAILS_MASTER_KEY}")" \
docker stack deploy \
  --compose-file "$ROOT/deploy/orchestration-dev.stack.yml" \
  --with-registry-auth \
  "${STACK}"

echo "==> Force-updating web"
docker service update --force --detach "${STACK}_web"

echo "✓ Deploy ${TAG} concluído"
echo "   URL: https://orchestration-dev.redhusky.com.br"
echo "   web: $(docker service ps ${STACK}_web --format '{{.CurrentState}}' | head -1)"

echo "==> Limpando imagens antigas"
docker image prune -af --filter "until=24h" || true
docker builder prune -af --reserved-space 10GB || true
