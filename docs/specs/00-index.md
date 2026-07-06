# Orchestration RedHusky — Specs Index

> Specs futuras (feature-*.md). Implementadas moram no ROADMAP.md e nos
> SPEC-*.md do root. Lacunas vs Portainer mapeadas em
> `githusky:docs/comparativo-plataformas.md`.

| Spec | O quê | Status | Ordem |
|---|---|---|---|
| [feature-rbac-enforcement](feature-rbac-enforcement.md) | Roles admin/operator/viewer enforced (concern único + audit_entries) | 📋 | **1º — destrava as demais** |
| [feature-logs-streaming](feature-logs-streaming.md) | Logs live via SSE/Rack hijack (Fase 14; NÃO ActionCable — lição do ttyd) | 📋 | 2º |
| [feature-file-browser-write](feature-file-browser-write.md) | Upload/edit/delete no file browser (PUT archive) — exige RBAC antes | 📋 | 3º |
| [feature-app-templates](feature-app-templates.md) | Deploy 1-clique com templates da casa (Rails RedHusky, PG, Redis) | 📋 | 4º |
| [feature-edge-compute](feature-edge-compute.md) | Multi-endpoint via agente Go (enroll/heartbeat/tunnel — beta no repo) | 📋 | gatilho: 2º host |
| [feature-runtime-abstraction-podman](feature-runtime-abstraction-podman.md) | Abstração de runtime (Podman) | 📋 | sem gatilho |
| [feature-kubernetes-k3s](feature-kubernetes-k3s.md) | k3s single-node | ❌ fora de escopo (decisão na matriz) | — |
| [feature-kubernetes-k8s-multicluster](feature-kubernetes-k8s-multicluster.md) | k8s multi-cluster | ❌ fora de escopo | — |

📋 futura (gatilhos no doc) · ❌ decisão de não fazer enquanto o lab for Swarm single-host
