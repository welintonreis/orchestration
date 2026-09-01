# Orchestration RedHusky — Specs Index

> Specs futuras (feature-*.md). Implementadas moram no ROADMAP.md e nos
> SPEC-*.md do root. Lacunas vs Portainer mapeadas em
> `githusky:docs/comparativo-plataformas.md`.

| Spec | O quê | Status | Ordem |
|---|---|---|---|
| [feature-rbac-enforcement](feature-rbac-enforcement.md) | Roles admin/operator/viewer enforced (concern único + audit_entries) | ✅ | shipped |
| [feature-logs-streaming](feature-logs-streaming.md) | Logs live via ActionCable (LogsChannel) | ✅ | shipped |
| [feature-file-browser-write](feature-file-browser-write.md) | Upload/edit/delete no file browser (PUT archive) | ✅ | shipped |
| [feature-app-templates](feature-app-templates.md) | Deploy 1-clique com templates da casa (Rails RedHusky, PG, Redis, static) | ✅ | shipped (2026-07-06) |
| [feature-kubernetes-k3s](feature-kubernetes-k3s.md) | k3s single-node | ✅ | shipped v0.9.17 |
| [feature-kubernetes-k8s-multicluster](feature-kubernetes-k8s-multicluster.md) | k8s multi-cluster | ✅ (parcial) | shipped v0.9.17 |
| [feature-edge-compute](feature-edge-compute.md) | Multi-endpoint via agente Go (enroll/heartbeat/tunnel — beta no repo) | 📋 | gatilho: 2º host |
| [feature-loading-skeletons](feature-loading-skeletons.md) | Skeletons de loading + cache de capabilities + barra de progresso do Turbo | 🚧 | em andamento |
| [feature-ai-quota](feature-ai-quota.md) | Quotas de IA nativas (contas próprias, refresh de token, snapshots) | 📋 | próxima |
| [feature-runtime-abstraction-podman](feature-runtime-abstraction-podman.md) | Abstração de runtime (Podman) | 📋 | sem gatilho |

## Incidentes

| Doc | O quê |
|---|---|
| [incident-terminal-vps-selecao](incident-terminal-vps-selecao.md) | Terminal VPS: seleção/cópia morta (tmux `mouse on`), 2ª sessão impossível, shells órfãos — corrigido v0.9.60 |

✅ implementado · 📋 futura (gatilhos no doc) · ❌ decisão de não fazer
