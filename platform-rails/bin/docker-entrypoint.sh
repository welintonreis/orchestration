#!/bin/bash
set -e

# Detect docker socket GID at runtime and grant rails user access.
# This makes the image portable — no hardcoded GID needed.
if [ -S /var/run/docker.sock ]; then
  DOCKER_GID=$(stat -c '%g' /var/run/docker.sock)
  if ! getent group "$DOCKER_GID" > /dev/null 2>&1; then
    groupadd -g "$DOCKER_GID" docker_host
  fi
  usermod -aG "$DOCKER_GID" rails 2>/dev/null || true
fi

exec gosu rails "$@"
