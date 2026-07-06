# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end

# githusky-style app templates (feature-app-templates.md) — the RedHusky
# house defaults. find_or_create_by! only touches the row on first seed;
# an admin who's since edited one of these in the panel keeps their edits
# on every subsequent boot (db:prepare only reseeds a brand-new database).
[
  {
    name: "Rails RedHusky",
    description: "App Rails 8 padrão da casa — Traefik websecure+LE, network traefik + postgres-cluster, healthcheck /up.",
    icon: "server",
    variables: { "APP_NAME" => "nome do serviço (ex.: meuapp)", "IMAGE" => "imagem:tag (ex.: meuapp:v1.0.0)", "DOMAIN" => "domínio público (ex.: meuapp.redhusky.com.br)" },
    compose_yaml: <<~YAML
      version: "3.8"
      services:
        web:
          image: {{IMAGE}}
          networks: [traefik, postgres-cluster]
          environment:
            RAILS_ENV: production
          healthcheck:
            test: ["CMD", "wget", "-qO-", "http://localhost:3000/up"]
            interval: 30s
            timeout: 5s
            retries: 3
          deploy:
            labels:
              - "traefik.enable=true"
              - "traefik.http.routers.{{APP_NAME}}.rule=Host(`{{DOMAIN}}`)"
              - "traefik.http.routers.{{APP_NAME}}.entrypoints=websecure"
              - "traefik.http.routers.{{APP_NAME}}.tls.certresolver=letsencrypt"
              - "traefik.http.services.{{APP_NAME}}.loadbalancer.server.port=3000"
      networks:
        traefik:
          external: true
        postgres-cluster:
          external: true
    YAML
  },
  {
    name: "Postgres efêmero",
    description: "Instância de teste — sem volume persistente, dados somem ao remover o stack.",
    icon: "database",
    variables: { "STACK_NAME" => "nome do serviço (ex.: pgtest)", "POSTGRES_PASSWORD" => "senha do usuário postgres" },
    compose_yaml: <<~YAML
      version: "3.8"
      services:
        postgres:
          image: postgres:17-alpine
          networks: [postgres-cluster]
          environment:
            POSTGRES_PASSWORD: {{POSTGRES_PASSWORD}}
      networks:
        postgres-cluster:
          external: true
    YAML
  },
  {
    name: "Redis efêmero",
    description: "Cache/fila de teste — sem persistência, some ao remover o stack.",
    icon: "zap",
    variables: {},
    compose_yaml: <<~YAML
      version: "3.8"
      services:
        redis:
          image: redis:7-alpine
          networks: [postgres-cluster]
      networks:
        postgres-cluster:
          external: true
    YAML
  },
  {
    name: "Static site",
    description: "Nginx servindo um build estático (SPA/site), atrás do Traefik.",
    icon: "globe",
    variables: { "APP_NAME" => "nome do serviço", "IMAGE" => "imagem com o build já embutido (ex.: meusite:v1)", "DOMAIN" => "domínio público" },
    compose_yaml: <<~YAML
      version: "3.8"
      services:
        web:
          image: {{IMAGE}}
          networks: [traefik]
          deploy:
            labels:
              - "traefik.enable=true"
              - "traefik.http.routers.{{APP_NAME}}.rule=Host(`{{DOMAIN}}`)"
              - "traefik.http.routers.{{APP_NAME}}.entrypoints=websecure"
              - "traefik.http.routers.{{APP_NAME}}.tls.certresolver=letsencrypt"
              - "traefik.http.services.{{APP_NAME}}.loadbalancer.server.port=80"
      networks:
        traefik:
          external: true
    YAML
  }
].each do |attrs|
  AppTemplate.find_or_create_by!(name: attrs[:name]) do |t|
    t.description  = attrs[:description]
    t.icon         = attrs[:icon]
    t.variables    = attrs[:variables]
    t.compose_yaml = attrs[:compose_yaml]
    t.built_in     = true
  end
end
