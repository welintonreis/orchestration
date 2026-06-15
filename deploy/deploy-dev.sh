#!/usr/bin/env bash
# deploy-dev.sh — build local + deploy dev (sem registry).
# Uso: bash deploy/deploy-dev.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$ROOT/deploy/.env.dev"
VERSION="$(cat "$ROOT/platform-rails/VERSION" 2>/dev/null || echo "0.1.0")"
IMAGE="orchestration:v${VERSION}"

if [[ -f "$ENV_FILE" ]]; then
  set -a; source "$ENV_FILE"; set +a
else
  echo "ERRO: $ENV_FILE não encontrado. Crie a partir de deploy/.env.dev.example"
  exit 1
fi

export IMAGE

echo "==> Building $IMAGE"
docker build --no-cache -t "$IMAGE" "$ROOT/platform-rails/"

echo "==> Deploying stack ${STACK_NAME}"
docker stack deploy \
  -c "$ROOT/deploy/orchestration.stack.yml" \
  --with-registry-auth \
  "$STACK_NAME"

echo "==> Force-updating web"
docker service update --force --detach "${STACK_NAME}_web"

echo "✓ Deploy v${VERSION} concluído"
echo "   web: $(docker service ps ${STACK_NAME}_web --format '{{.CurrentState}}' | head -1)"

echo "==> Limpando imagens antigas"
docker image prune -af --filter "until=24h" || true
docker builder prune -af --reserved-space 10GB || true
