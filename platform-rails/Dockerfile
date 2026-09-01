# syntax=docker/dockerfile:1
ARG RUBY_VERSION=3.3.11

# ── Stage 1: Base ─────────────────────────────────────────────
FROM ruby:${RUBY_VERSION}-slim AS base
WORKDIR /rails

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      build-essential \
      curl \
      git \
      libpq-dev \
      libvips \
      libyaml-dev \
      pkg-config \
      sqlite3 \
    && rm -rf /var/lib/apt/lists/*

ENV RAILS_ENV=production \
    BUNDLE_DEPLOYMENT=1 \
    BUNDLE_WITHOUT="development test" \
    BUNDLE_PATH="/usr/local/bundle"

# ── Stage 2: Bundle install ────────────────────────────────────
FROM base AS deps
COPY Gemfile Gemfile.lock ./
RUN bundle install --jobs 4 --retry 3 && \
    rm -rf "${BUNDLE_PATH}/ruby/*/cache" \
           "${BUNDLE_PATH}/ruby/*/bundler/gems/*/.git"

# ── Stage 3: Assets precompile ─────────────────────────────────
FROM base AS assets
COPY --from=deps /usr/local/bundle /usr/local/bundle
COPY . .
RUN bundle exec rails assets:precompile

# ── Stage 4: Final image ───────────────────────────────────────
FROM ruby:${RUBY_VERSION}-slim AS final
WORKDIR /rails

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      acl \
      curl \
      dtach \
      gosu \
      libpq5 \
      libvips \
      git \
    && rm -rf /var/lib/apt/lists/*

# GitDeployer shells out to the docker CLI ("docker stack deploy" / "docker
# compose") — everything else in this app talks to the daemon over the
# socket via the Excon-based DockerClient, so this is the only thing in the
# image that needed the actual binary, and it was never installed. Static
# binary (no daemon bundled) — docker CLI negotiates API version with
# whatever daemon it connects to, so an exact version match isn't required.
RUN ARCH=$(dpkg --print-architecture) && \
    case "$ARCH" in \
      amd64) DARCH=x86_64 ;; \
      arm64) DARCH=aarch64 ;; \
      *) echo "unsupported architecture: $ARCH" && exit 1 ;; \
    esac && \
    curl -fsSL "https://download.docker.com/linux/static/stable/${DARCH}/docker-27.3.1.tgz" -o /tmp/docker.tgz && \
    tar xzf /tmp/docker.tgz --strip-components=1 -C /usr/local/bin docker/docker && \
    rm /tmp/docker.tgz && \
    chmod +x /usr/local/bin/docker

# ttyd — serves an interactive PTY (docker exec) over a loopback WebSocket.
# ContainersController#ttyd_ws proxies the browser WS to it, replacing the
# ActionCable + Solid Cable terminal transport (SQLite polling → ~100ms
# keystroke lag). Static binary, no runtime deps.
RUN ARCH=$(dpkg --print-architecture) && \
    case "$ARCH" in \
      amd64) TARCH=x86_64 ;; \
      arm64) TARCH=aarch64 ;; \
      *) echo "unsupported architecture: $ARCH" && exit 1 ;; \
    esac && \
    curl -fsSL "https://github.com/tsl0922/ttyd/releases/download/1.7.7/ttyd.${TARCH}" \
         -o /usr/local/bin/ttyd && \
    chmod +x /usr/local/bin/ttyd

# kubectl — KubeClient shells out to it for apply/exec (server-side merge
# and SPDY/WebSocket-multiplexed exec, both not worth reimplementing over
# the raw REST API). Pinned version, not the "latest" redirect, so a Swarm
# redeploy never silently picks up a new kubectl behind everyone's back.
RUN ARCH=$(dpkg --print-architecture) && \
    curl -fsSL "https://dl.k8s.io/release/v1.31.4/bin/linux/${ARCH}/kubectl" \
         -o /usr/local/bin/kubectl && \
    chmod +x /usr/local/bin/kubectl

COPY --from=deps  /usr/local/bundle /usr/local/bundle
COPY --from=assets /rails/public/assets ./public/assets
COPY . .

ENV RAILS_ENV=production \
    BUNDLE_DEPLOYMENT=1 \
    BUNDLE_WITHOUT="development test" \
    BUNDLE_PATH="/usr/local/bundle" \
    RAILS_LOG_TO_STDOUT=true \
    RAILS_SERVE_STATIC_FILES=true

RUN useradd --create-home --shell /bin/bash rails && \
    mkdir -p db log storage tmp && \
    chown -R rails:rails db log storage tmp

RUN chmod +x ./bin/docker-entrypoint.sh

EXPOSE 80
ENTRYPOINT ["./bin/docker-entrypoint.sh"]
CMD ["./bin/thrust", "./bin/rails", "server"]
