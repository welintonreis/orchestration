# Spec — RBAC enforcement (v1.1)

**Status:** ✅ implementado — `Authorization` concern (fail-closed por
verbo, POLICY map único, scoping por time+environment) já shippado antes
desta verificação (2026-07-06); esta spec só documentava uma pendência
do ROADMAP que já não existia mais no código.

## Gatilhos

1. Segundo usuário humano no painel (hoje single-admin — enforcement é
   teatro de segurança).
2. Dar acesso "só leitura" a alguém (cliente/estagiário vendo logs).

## Problema

Roles existem no modelo de User mas nenhum controller as verifica: todo
usuário autenticado é efetivamente admin (pode exec em container, rm de
stack, editar settings).

## Desenho

- 3 roles fixas (sem matriz custom): **admin** (tudo), **operator**
  (start/stop/restart/scale/deploy, terminal, logs; sem settings, users,
  rm de volumes/stacks), **viewer** (read-only: dashboard, logs, inspect;
  sem exec/terminal — terminal é RCE, viewer nunca).
- Enforcement por **concern único** (`Authorizable`): `require_role!
  (:operator)` como before_action nos controllers de mutação, mapa
  ação→role mínimo num só lugar (constante), não espalhado. Padrão
  Pundit não vale a pena aqui (recursos Docker não são AR records).
- UI: seletor de role em Settings → Users; badges; botões destrutivos
  escondidos pra quem não pode (defesa real é o server-side).
- Auditoria: reusar o log de alertas — toda ação de mutação vira linha
  (user, ação, alvo) numa tabela `audit_entries` simples.
- **Fora**: RBAC por environment/endpoint (quando multi-endpoint sair do
  beta), teams.

## Custo

1 sessão. Teste-chave: viewer tentando POST em cada rota de mutação → 403.
