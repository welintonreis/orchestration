# Spec: Kubernetes — Fase 1 (k3s single-node)

> Criado: 2026-07-02 | Status: implementado — v0.9.17 | Autor: Claude/Welinton
> Depende de: `feature-runtime-abstraction-podman.md` (conceito de capability por environment)

> Implementado: `KubeClient` (Excon + kubectl shellout p/ apply/exec, mesma
> filosofia do `DockerClient`), migration `environments.kube_*` (+ `encrypts`
> real via Active Record Encryption — chaves geradas e adicionadas às
> credentials nesta sessão), telas `Kube::` completas (Workloads/Pods/
> Services/ConfigMaps/Secrets/Nodes/Apply), sidebar troca Docker/Swarm por
> Kubernetes quando o environment ativo é k8s, terminal via ttyd+kubectl exec
> (kubeconfig temporário, token nunca no argv), `GitStack#deploy_mode
> "kubernetes"` (kubectl apply/delete), kubectl instalado no Dockerfile
> (pinado v1.31.4, testado no build real). Testado via Excon stub (mesmo
> padrão do DockerClient) — sem k3s real neste host por decisão explícita
> (evitar mudar infra do host de produção só para verificação).
>
> Desvios/cortes de escopo:
> - **Logs sem streaming ao vivo na UI** — `KubeClient#pod_logs` já suporta
>   `follow:` (chunked), mas a tela renderiza snapshot estático (like
>   `container_logs` antes do LogsChannel). Streaming fica pra depois.
> - **kubectl exec sem troca de usuário** — ao contrário de `docker exec -u`,
>   `kubectl exec` não tem flag equivalente; não implementado (usaria `su`
>   dentro do container, frágil e fora de escopo).
> - **effective_endpoint não usado por ambientes k8s** — Docker/TtydManager/
>   GitDeployer continuam intocados; k8s tem seu próprio client e telas
>   inteiramente separados (por design, ver Anti-patterns).

## Objetivo

Gerenciar um cluster k3s (single-node primeiro) pelo painel: workloads, pods,
logs, terminal, deploy de manifests — o divisor que separa Portainer/Rancher
do resto dos painéis Docker.

## Contexto

k3s = Kubernetes certificado em 1 binário (~70MB), ideal para o perfil
RedHusky (VPS única, edge boxes). É o degrau de entrada para k8s: a API é
idêntica, só muda o provisioning. Fase 1 mira k3s local/único; multi-cluster
genérico fica na fase 2 (`feature-kubernetes-k8s-multicluster.md`).

A API k8s **não tem nada a ver** com a Docker API — não é um novo endpoint no
`DockerClient`, é um cliente novo. O que reaproveitamos: TODO o chrome da UI
(tabelas, rows/turbo-frames, filtros, paginação, bulk), o terminal ttyd
(via `kubectl exec`), auditoria, RBAC do painel, alertas.

Alternativa descartada: gem `k8s-ruby`/`kubeclient` — abandonware ou pesadas;
a API REST do k8s é regular o bastante para um client Excon fino (mesma
filosofia do `DockerClient`). Watch/streaming via HTTP chunked que o Excon já
faz (`response_block`).

## Interface

### Entrada
- `Environment` ganha `endpoint_type: "kubernetes"` + campos:
  `kube_api_url` (ex.: `https://127.0.0.1:6443`), `kube_ca_cert` (PEM),
  `kube_token` (ServiceAccount token, **criptografado** — `encrypts` do Rails).
  Para k3s local: botão "importar de /etc/rancher/k3s/k3s.yaml" (parse do
  kubeconfig: cluster.server, certificate-authority-data, token do user).
- Seletor de environment existente troca o "modo" da navegação:
  environment k8s → sidebar mostra seção Kubernetes, esconde Docker/Swarm.

### Saída
- Novas telas (namespace-scoped, seletor de namespace no topo):
  - **Workloads**: Deployments/StatefulSets/DaemonSets — réplicas, imagem,
    status, scale (PATCH `/apis/apps/v1/.../scale`), restart
    (patch em `spec.template.metadata.annotations["kubectl.kubernetes.io/restartedAt"]`), delete.
  - **Pods**: lista com fase/restarts/node; logs
    (`GET /api/v1/namespaces/{ns}/pods/{p}/log?follow=true` → stream no canal
    de logs existente); terminal (abaixo); delete (= restart do controller).
  - **Services/Ingress**: leitura + delete.
  - **ConfigMaps/Secrets**: CRUD (paridade com configs/secrets swarm).
  - **Apply manifest**: textarea YAML → `kubectl apply -f -` server-side
    (via CLI vendorizado) — o "deploy de stack" do mundo k8s.
  - **Nodes**: capacidade/pressão/versão (fase 1 mostra o único node k3s).
- `GitStack` ganha `deploy_mode: "kubernetes"` → `GitDeployer` roda
  `kubectl apply -k`/`-f` do repo clonado (GitOps igual ao de compose,
  reusa poll/webhook/drift/revisões).

### Restrições não-funcionais
- Terminal: mesma latência do fix v0.9.14 (<20ms echo) — ttyd + `kubectl exec -it`.
- Token do cluster: `Rails.encrypts` na coluna, nunca em log/audit metadata.
- Timeout padrão 10s por request; watch/log streams sem timeout (como hoje).
- k3s embutido tem métricas via metrics-server (`/apis/metrics.k8s.io`) —
  usar se instalado, esconder colunas se 404.

## Implementação

### Arquivos a criar/modificar
- `app/services/kube_client.rb` — Excon + bearer token + CA custom
  (`ssl_ca_file`/`ssl_cert_store`), JSON, métodos: `namespaces`, `pods(ns:)`,
  `deployments(ns:)`, `scale(kind, name, ns:, replicas:)`, `pod_logs(… , follow:)`,
  `apply(yaml)` (shell out `kubectl apply`), `delete(kind, name, ns:)`,
  `nodes`, `top_pods` (metrics-server). Erros tipados iguais aos do DockerClient.
- `app/services/ttyd_manager.rb` — comando por environment k8s:
  `["kubectl", "--server", url, "--token", tok, "--certificate-authority", ca_file,
  "exec", "-it", "-n", ns, pod, "-c", container, "--", "/bin/sh", "-c",
  "command -v bash >/dev/null 2>&1 && exec bash; exec sh"]`
  (mesma lição do stderr do postmortem!). Token via arquivo tmp 0600, não argv…
  → melhor: gerar kubeconfig tmp e passar `KUBECONFIG=` env (token fora do argv,
  invisível no /proc).
- `Dockerfile` — instalar `kubectl` (binário estático, pinado por versão).
- `app/controllers/kube/*_controller.rb` — namespace `Kube::` espelhando o
  padrão `Swarm::` (workloads, pods, services, config, apply).
- `config/routes.rb` — `namespace :kube`.
- `app/models/environment.rb` — `ENDPOINT_TYPES << "kubernetes"`, validações
  condicionais, `encrypts :kube_token`.
- Views — copiar padrão rows/turbo-frame das telas containers.

### Decisões técnicas
- **Excon fino + kubectl para exec/apply**: API REST para leitura/ação simples
  (rápido, sem deps), CLI oficial para os dois fluxos que têm semântica
  complexa (exec com SPDY/WebSocket multiplexado; apply com server-side
  merge). Evita reimplementar o protocolo v5.channel.k8s.io.
- **Namespace como filtro primário** — mapeia mental model de "stack".
- **ServiceAccount dedicado** documentado no help: criar SA `orchestration`
  com ClusterRole limitado (get/list/watch/patch/delete em workloads, exec em
  pods) em vez do token admin do k3s.yaml — least privilege.

### Anti-patterns a evitar
- NÃO misturar KubeClient no DockerClient (protocolos diferentes; capability
  switch fica no Environment, não no client).
- NÃO guardar kubeconfig inteiro em plaintext no banco.
- NÃO fazer watch de TUDO no dashboard (k8s watch = firehose) — polling nas
  telas como hoje, watch só em log/terminal.
- NÃO passar token no argv do kubectl (visível em /proc de todo o container).

## Testes

- [ ] Happy path: k3s local (curl -sfL https://get.k3s.io | sh) cadastrado,
      lista pods/deployments, scale, delete pod, logs stream
- [ ] Terminal em pod nginx: prompt <300ms, eco <20ms (probe do postmortem)
- [ ] Apply manifest inválido → erro do server exibido, nada aplicado
- [ ] Token errado/expirado → tela mostra 401 claro, sem stacktrace
- [ ] Environment Docker intocado (regressão zero na suite)
- [ ] Deploy testado em staging

## Rollout

Migration aditiva em environments. Feature invisível até cadastrar um
environment kubernetes. k3s de teste pode rodar no próprio lab-01
(`k3s server --docker=false`, cuidado com conflito de portas 6443/traefik k3s
→ instalar com `--disable traefik`). Reversível: remover environment.
