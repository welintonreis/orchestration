# Spec: Kubernetes — Fase 2 (k8s genérico, multi-cluster)

> Criado: 2026-07-02 | Status: draft | Autor: Claude/Welinton
> Depende de: `feature-kubernetes-k3s.md` (KubeClient, telas Kube::, ttyd+kubectl)

## Objetivo

Estender a fase 1 (k3s) para qualquer cluster Kubernetes conformante — EKS/GKE/
AKS/kubeadm/k3s remoto — vários clusters simultâneos, com RBAC do painel
mapeando permissões por cluster.

## Contexto

A fase 1 entrega o cliente e as telas; a fase 2 é sobre **gestão de N clusters
heterogêneos**: kubeconfigs multi-context, auth plugins de cloud, versões de
API divergentes, e times com acesso a clusters diferentes. Portainer BE e
Rancher cobram exatamente por isso — é o teto competitivo do painel.

Alternativa descartada: agente instalado no cluster (modelo Rancher/Portainer
agent) — poderoso (atravessa NAT, não expõe API server), mas duplica o esforço
do edge agent Docker. O modelo de **acesso direto à API** cobre clusters
alcançáveis; clusters atrás de NAT entram pelo túnel do edge agent
(`feature-edge-compute.md`, que passa a transportar também a API k8s).

## Interface

### Entrada
- **Import de kubeconfig completo** (upload/paste): parse de todos os
  contexts → cria 1 Environment kubernetes por context (nome =
  `cluster/context`). Suporta `client-certificate-data`+`client-key-data`
  (mTLS) além de token — novos campos criptografados
  `kube_client_cert`, `kube_client_key`.
- **Auth exec plugins** (aws eks get-token, gke-gcloud-auth-plugin): fase 2.1
  opcional — campo `kube_exec_credential_cmd` (admin-only, mesmo tratamento
  de segurança dos hooks do GitDeployer). Sem ele, exigir token de SA
  long-lived (documentado como caminho recomendado).
- Grupos de environments existentes (`ambiente/groups`) passam a agrupar
  clusters; teams ganham escopo por environment (ver Saída/RBAC).

### Saída
- **Seletor multi-cluster**: dropdown atual de environment já resolve; adicionar
  coluna "cluster version/health" na lista de environments (GET `/version` +
  `/readyz` de cada, em paralelo, cacheado 60s).
- **Visão fleet** (nova tela `kube/fleet`): matriz cluster × (nodes ready,
  pods failed, deployments degraded, versão) — o "single pane of glass".
- **RBAC por environment**: tabela `team_environment_permissions`
  (team_id, environment_id, role readonly/operator/admin). `Authorization`
  passa a considerar o environment ativo: operator global vira operator só
  nos clusters do time. Docker environments ganham o mesmo controle de graça.
- **Drift GitOps multi-cluster**: `GitStack` com environment k8s aponta
  kustomize overlay por cluster (`overlays/<env-name>/`), drift comparando
  `kubectl diff` (exit code 1 = drift) — reusa a máquina de estados
  synced/drifted existente.

### Restrições não-funcionais
- Fleet view com N clusters: chamadas em paralelo (padrão do dashboard
  v0.9.15), timeout 5s por cluster, cluster fora do ar não bloqueia a tela.
- Certs/keys/tokens: `encrypts` em todas as colunas; export proibido.
- Compatibilidade: testar contra skew de 2 minor versions (política oficial
  k8s); nada de APIs alpha; `apps/v1` + `core/v1` + `networking.k8s.io/v1`
  cobrem as telas.

## Implementação

### Arquivos a criar/modificar
- `app/services/kube_client.rb` — mTLS (client cert/key), exec credential
  (fase 2.1), version/health probes.
- `app/services/kubeconfig_importer.rb` — parse YAML multi-context →
  Environments (transação, valida conectividade de cada um antes de salvar).
- `app/models/team_environment_permission.rb` + migration.
- `app/controllers/concerns/authorization.rb` — `require_operator!` etc.
  recebem o environment ativo; helper `can?(action, environment)`.
- `app/controllers/kube/fleet_controller.rb` + view matriz.
- `app/services/git_drift_service.rb` — strategy k8s (`kubectl diff`).

### Decisões técnicas
- **1 Environment por context** (não 1 por kubeconfig): mantém o modelo mental
  e o seletor atuais; kubeconfig é só um importador.
- **RBAC no painel, não no cluster**: o painel usa a credencial do cluster
  (poderosa) mas filtra ações pela permissão do time — auditável num lugar só.
  Ações sempre em AuditLog com environment_id.
- **`kubectl diff` para drift** em vez de reimplementar three-way merge —
  é literalmente o que o kubectl faz melhor.

### Anti-patterns a evitar
- NÃO fazer proxy genérico da API k8s pro browser (superfície de ataque
  gigante) — só endpoints curados.
- NÃO cachear tokens exec-plugin além do TTL retornado.
- NÃO permitir editar `kube_exec_credential_cmd` a não-admin (é RCE por design).

## Testes

- [ ] Import kubeconfig com 3 contexts → 3 environments funcionais
- [ ] Cluster inacessível na fleet view → célula "offline", demais renderizam
- [ ] Team restrito a cluster A não vê/atua no cluster B (controller + view)
- [ ] mTLS auth (client cert) contra kubeadm; token SA contra k3s
- [ ] Drift: editar replicas via kubectl direto → stack marcada drifted
- [ ] Deploy testado em staging

## Rollout

Ordem: RBAC por environment (vale para Docker também) → import kubeconfig →
fleet view → drift k8s. Cada etapa deployável sozinha. Migrations aditivas;
RBAC novo default = comportamento atual (times sem registros = acesso global,
zero breaking).
