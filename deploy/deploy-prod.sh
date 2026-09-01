#!/usr/bin/env bash
# deploy-prod.sh — build local + deploy prod stack via versioned tag (sem registry)
# Usage: ./deploy/deploy-prod.sh [bump]   bump = patch++ before build
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [[ "${1:-}" == "bump" ]]; then
  v=$(cat "$ROOT/VERSION"); IFS=. read -r a b c <<<"$v"; echo "$a.$b.$((c+1))" > "$ROOT/VERSION"
  echo "Bumped: $v -> $(cat "$ROOT/VERSION")"
fi

VERSION="$(cat "$ROOT/VERSION")"
TAG="v${VERSION}"
IMAGE="redhusk/orchestration:${TAG}"
STACK="orchestration-prod"

echo "==> Version: ${VERSION}  Image: ${IMAGE}"

docker build \
  --platform linux/amd64 \
  -t "${IMAGE}" \
  "$ROOT/platform-rails/"

# Ensure host bind-mount path exists before Swarm schedules the task.
mkdir -p "${GIT_WORKSPACE_HOST_PATH:-/srv/redhusky/git-stacks}"

MASTER_KEY="$(cat "$ROOT/platform-rails/config/master.key" 2>/dev/null || echo "${RAILS_MASTER_KEY:-}")"

# App -> HAProxy -> PgBouncer -> Postgres (primary/réplicas), ver
# ~/docker/postgres/README.md. Senha em .db_password (gitignored).
DB_PASSWORD="$(cat "$ROOT/.db_password")"
DATABASE_URL="postgresql://orchestration_app:${DB_PASSWORD}@haproxy:6432/orchestration"

echo "==> Deploying stack ${STACK}"
# Note: db:prepare runs inside the entrypoint on first start (bin/docker-entrypoint.sh).
IMAGE="${IMAGE}" \
RAILS_MASTER_KEY="${MASTER_KEY}" \
DATABASE_URL="${DATABASE_URL}" \
docker stack deploy \
  --compose-file "$ROOT/deploy/orchestration.stack.yml" \
  --resolve-image never \
  --detach=false \
  "${STACK}"

echo "==> Services"
docker service ls --filter "name=${STACK}"

echo "✓ Deploy ${TAG} concluído"
echo "   URL: https://orchestration.redhusky.com.br"
