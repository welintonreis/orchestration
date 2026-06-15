#!/usr/bin/env bash
set -euo pipefail

REPO="registry.gitlab.redhusky.com.br/redhusk/orchestration"
TAG="${1:-latest}"
IMAGE="${REPO}:${TAG}"
STACK="orchestration-prod"

echo "==> Building Rails image: ${IMAGE}"
docker build \
  --platform linux/amd64 \
  -t "${IMAGE}" \
  platform-rails/

echo "==> Pushing to registry"
docker push "${IMAGE}"

echo "==> Deploying stack ${STACK}"
IMAGE="${IMAGE}" \
RAILS_MASTER_KEY="$(cat platform-rails/config/master.key 2>/dev/null || echo "${RAILS_MASTER_KEY}")" \
docker stack deploy \
  --compose-file deploy/orchestration.stack.yml \
  --with-registry-auth \
  "${STACK}"

echo "==> Done. Service:"
docker service ls --filter "name=${STACK}_web"
