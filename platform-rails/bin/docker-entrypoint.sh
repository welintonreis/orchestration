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

# Git stacks get cloned here. Must be a host bind mount at the SAME path
# on both sides (not just any path inside the container) — GitDeployer
# runs "docker stack deploy" from inside this container, but the daemon
# it talks to runs on the bare host, so a compose file's relative bind
# mounts (e.g. "./app:/app") only resolve correctly on the host side if
# the absolute path the CLI computes (based on where it sees the cloned
# repo) is the same absolute path the host filesystem actually has it at.
if [ -n "$GIT_WORKSPACE_HOST_PATH" ]; then
  mkdir -p "$GIT_WORKSPACE_HOST_PATH"
  chown -R rails:rails "$GIT_WORKSPACE_HOST_PATH"
fi

gosu rails bin/rails db:migrate 2>&1

exec gosu rails "$@"
