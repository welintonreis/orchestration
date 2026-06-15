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
      libsqlite3-dev \
      libvips \
      pkg-config \
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
      curl \
      libsqlite3-0 \
      libvips \
      git \
    && rm -rf /var/lib/apt/lists/*

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

USER rails

EXPOSE 80
CMD ["./bin/thrust", "./bin/rails", "server", "-b", "0.0.0.0", "-p", "80"]
