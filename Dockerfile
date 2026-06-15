# syntax=docker/dockerfile:1

ARG GO_VERSION=1.25.11
ARG NODE_VERSION=22

# ── Stage 1: Build CSS ────────────────────────────────────────────────────────
FROM node:${NODE_VERSION}-alpine AS css-builder
WORKDIR /build
COPY package.json package-lock.json ./
RUN npm ci
COPY tailwind.config.js ./
COPY web/css ./web/css
COPY web/templates ./web/templates
RUN npm run build:css

# ── Stage 2: Build Go binary ──────────────────────────────────────────────────
FROM golang:${GO_VERSION}-alpine AS go-builder
WORKDIR /app

# Dependencies first (layer cache)
COPY go.mod go.sum ./
RUN go mod download

# Source + built CSS
COPY . .
COPY --from=css-builder /build/web/static/css ./web/static/css

RUN CGO_ENABLED=0 GOOS=linux go build \
      -ldflags="-s -w" \
      -o orchestration .

# ── Stage 3: Final image ──────────────────────────────────────────────────────
FROM alpine:3.20
RUN apk add --no-cache ca-certificates tzdata && \
    addgroup -S app && adduser -S app -G app
USER app
WORKDIR /app
COPY --from=go-builder /app/orchestration ./orchestration
EXPOSE 80
ENTRYPOINT ["./orchestration"]
