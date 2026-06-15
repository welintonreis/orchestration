#!/usr/bin/env bash
# deploy-prod.sh — build local + deploy prod.
# Uso: bash deploy/deploy-prod.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$ROOT/deploy/.env.prod"
VERSION="$(cat "$ROOT/VERSION" 2>/dev/null || echo "0.1.0")"
IMAGE="orchestration:v${VERSION}"

if [[ -f "$ENV_FILE" ]]; then
  set -a; source "$ENV_FILE"; set +a
else
  echo "ERRO: $ENV_FILE não encontrado. Crie a partir de deploy/.env.dev.example"
  exit 1
fi

export IMAGE

echo "==> Building $IMAGE (Dockerfile multi-stage)"
docker build --no-cache -t "$IMAGE" "$ROOT/"

echo "==> Deploying stack ${STACK_NAME:-orchestration-prod}"
STACK_NAME="${STACK_NAME:-orchestration-prod}" \
docker stack deploy \
  -c "$ROOT/deploy/orchestration.stack.yml" \
  --with-registry-auth \
  "${STACK_NAME:-orchestration-prod}"

echo "==> Force-updating web service"
docker service update --force --detach "${STACK_NAME:-orchestration-prod}_web"

echo "✓ Deploy v${VERSION} concluído"
echo "   URL: https://${APP_HOST:-orchestration.redhusky.com.br}"
echo "   web: $(docker service ps ${STACK_NAME:-orchestration-prod}_web --format '{{.CurrentState}}' | head -1)"

echo "==> Limpando imagens antigas"
docker image prune -af --filter "until=24h" || true
docker builder prune -af --reserved-space 10GB || true
