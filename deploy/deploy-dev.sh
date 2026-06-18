#!/usr/bin/env bash
# deploy-dev.sh — build local + deploy dev stack via versioned tag (sem registry)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(cat "$ROOT/VERSION")"
TAG="dev-v${VERSION}"
IMAGE="redhusk/orchestration:${TAG}"
STACK="orchestration-dev"

echo "==> Version: ${VERSION}  Image: ${IMAGE}"

docker build \
  --platform linux/amd64 \
  -t "${IMAGE}" \
  "$ROOT/platform-rails/"

mkdir -p "${GIT_WORKSPACE_HOST_PATH:-/srv/redhusky/git-stacks-dev}"

echo "==> Deploying stack ${STACK}"
IMAGE="${IMAGE}" \
RAILS_MASTER_KEY="$(cat "$ROOT/platform-rails/config/master.key" 2>/dev/null || echo "${RAILS_MASTER_KEY:-}")" \
docker stack deploy \
  --compose-file "$ROOT/deploy/orchestration-dev.stack.yml" \
  --resolve-image never \
  "${STACK}"

echo "==> Updating service to ${IMAGE}"
docker service update \
  --image "${IMAGE}" \
  "${STACK}_web"

echo "✓ Deploy ${TAG} concluído"
echo "   URL: https://orchestration-dev.redhusky.com.br"

docker image prune -f --filter "label=stage=dev" 2>/dev/null || true
