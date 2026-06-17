#!/usr/bin/env bash
# deploy-prod.sh — build local + deploy prod stack via versioned tag (sem registry)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(cat "$ROOT/VERSION")"
TAG="v${VERSION}"
IMAGE="redhusk/orchestration:${TAG}"
STACK="orchestration-prod"

echo "==> Version: ${VERSION}  Image: ${IMAGE}"

docker build \
  --platform linux/amd64 \
  -t "${IMAGE}" \
  "$ROOT/platform-rails/"

# Swarm bind mounts require the host source path to exist before the
# container starts — the container's own entrypoint can't create it,
# that's too late (the scheduler already rejected the task by then).
mkdir -p "${GIT_WORKSPACE_HOST_PATH:-/root/docker/git-stacks}"

echo "==> Deploying stack ${STACK}"
IMAGE="${IMAGE}" \
RAILS_MASTER_KEY="$(cat "$ROOT/platform-rails/config/master.key" 2>/dev/null || echo "${RAILS_MASTER_KEY:-}")" \
docker stack deploy \
  --compose-file "$ROOT/deploy/orchestration.stack.yml" \
  --resolve-image never \
  "${STACK}"

echo "==> Updating service to ${IMAGE}"
docker service update \
  --image "${IMAGE}" \
  "${STACK}_web"

echo "✓ Deploy ${TAG} concluído"
echo "   URL: https://orchestration.redhusky.com.br"
