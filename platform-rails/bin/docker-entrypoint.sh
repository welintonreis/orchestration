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

# AiAccount reads/rewrites the CLIs' own credential files (600 root:root on
# the host). chown would fight the CLI, which still writes as root on its
# own refreshes; a default ACL grants rails rw without touching ownership,
# and — because it's a *default* ACL on the directory — the atomic
# rename(temp, target) used for the rewrite still inherits it on the new
# inode.
# /root itself is 700 root:root inside the container (rails' home is
# /home/rails) — without traverse rights here the ACLs below are unreachable.
setfacl -m u:rails:--x /root 2>/dev/null || true
for d in /root/.claude /root/.codex; do
  [ -d "$d" ] && setfacl -R -m u:rails:rwX -d -m u:rails:rwX "$d" 2>/dev/null || true
done

gosu rails bin/rails db:migrate 2>&1

exec gosu rails "$@"
