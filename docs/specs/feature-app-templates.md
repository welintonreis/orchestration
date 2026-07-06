# Spec — App templates (deploy 1-clique)

**Status:** ✅ implementado (2026-07-06) — `AppTemplate` model + galeria +
deploy via `docker stack deploy` (mesmo shellout do GitDeployer), guard
de segurança contra socket/host-path fora do allowlist, 4 templates da
casa seedados (Rails RedHusky, Postgres/Redis efêmero, Static site).
Versionamento de template (git do painel) não entrou — fora de escopo
declarado na spec original.

## Gatilhos

1. Terceira vez que se sobe o mesmo tipo de serviço colando compose na
   mão (postgres de teste, redis efêmero, app Rails padrão).
2. Onboarding de projeto novo virar rotina (padrão RedHusky: Rails 8 +
   Traefik labels + postgres-cluster).

## Desenho

- Tabela `app_templates` (name, description, icon, compose_yaml,
  variables jsonb) — template é um compose de stack com placeholders
  `{{VAR}}`.
- **Seed com os padrões da casa** (o valor real está aqui, não na
  feature): "Rails RedHusky" (imagem `:vX.Y.Z`, labels Traefik
  websecure+LE, network `traefik` + `postgres-cluster`, healthcheck
  `/up`), "Postgres efêmero", "Redis efêmero", "Static site".
- UI: galeria (cards) → form gerado das variables (name, domain,
  image tag...) → render do compose → `docker stack deploy` via o
  DockerClient existente → vira stack normal na listagem.
- Templates são **editáveis no painel** (textarea YAML + validação
  parse) — sem marketplace externo, sem URLs remotas (SSRF à toa).
- Guard: validar que o YAML renderizado não monta `/var/run/docker.sock`
  nem paths do host fora de allowlist — template é admin-editável, mas
  o deploy 1-clique será usado por operator (RBAC).
- **Fora**: templates de container avulso (stack cobre), versionamento
  de template (git do próprio painel resolve se doer).

## Custo

1-2 sessões. Depende de RBAC pra fazer sentido multi-role.
