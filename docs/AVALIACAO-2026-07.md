# Avaliação profunda — orchestration-redhusky

> Criado: 2026-07-02 | Base: v0.9.13 → v0.9.15 | Autor: Claude (sessão de auditoria)

## 1. O que foi corrigido nesta sessão

| Item | Causa raiz | Fix | Versão |
|---|---|---|---|
| **Terminal mudo/"parado"** | `exec bash 2>/dev/null` fixava stderr da sessão em /dev/null; bash interativo escreve prompt+echo no **stderr** | `command -v bash` probe, sem redirect; `-e TERM=xterm-256color` | v0.9.14 (postmortem em `SPEC-TERMINAL-TTYD.md`) |
| **Dashboard 5.5s** | 7 chamadas Docker API sequenciais (info, containers, images, volumes, networks, services, nodes) | Fan-out em threads, 1 `DockerClient` por thread | v0.9.15 |
| **`exec_create` legado** | mesmo bug de stderr no default cmd | mesmo fix | v0.9.15 |
| **CVEs de gems** | nokogiri (use-after-free), concurrent-ruby, crass | `bundle update --conservative`; `bundler-audit` limpo | v0.9.15 |

Números do terminal pós-fix (caminho completo via Traefik):
prompt ~250ms · echo p50 13ms · comando 9ms. Probe reutilizável documentado no postmortem.

## 2. Achados de revisão de código (por prioridade)

### Alta

1. **Endpoints `tcp://` sem TLS** (`DockerClient#build_connection`). Um endpoint
   remoto tcp:// fala HTTP puro com o daemon — credenciais de rede zero. Docker
   remoto exige mTLS (cert/key/CA) na porta 2376. Enquanto só o socket unix local
   é usado, ok; ao cadastrar o primeiro Environment remoto isso vira buraco
   crítico. → Spec edge/multi-node cobre a alternativa (agent outbound-only,
   melhor que expor 2376).
2. **API version hardcoded `/v1.47`** em todos os paths. Daemon mais velho
   (ou Podman) rejeita/degrada. Negociar via `GET /_ping` header `Api-Version`
   uma vez por client e cachear. Pré-requisito do suporte Podman
   (`docs/specs/feature-podman-runtime.md`).
3. **`ttyd_ws` sem verificação de Origin.** Auth por cookie de sessão protege
   (SameSite=Lax bloqueia WS cross-site nos browsers atuais), mas um check
   `request.origin == request.base_url` antes do hijack é defesa-em-profundidade
   barata contra CSWSH; ActionCable já faz isso por config.
4. **Rate limit só no login.** `SessionsController` tem `rate_limit`, mas ações
   destrutivas (remove/prune/bulk, deploy webhook `webhooks/:token/deploy`) não
   têm. Webhook token na URL: adicionar rate limit + comparação constante
   (`ActiveSupport::SecurityUtils.secure_compare`).

### Média

5. **Brakeman: 3 avisos de command injection** (git_poll/git_unpacker) — os
   argumentos vão em array (sem shell), então injeção real não há; mas
   `authenticated_url` embute token na URL de remote → token pode vazar em
   erro/log do git. Usar `GIT_ASKPASS`/credential helper ou header
   `http.extraHeader`. Os avisos de mass-assignment de `role` em
   `users_controller` são reais mas mitigados (rota admin-only); whitelistar
   `role` contra `User::ROLES` explicitamente de todo modo.
6. **`GitDeployer` hooks pre/post-sync** rodam shell arbitrário digitado no
   form como o processo do Rails (root no container com docker.sock montado =
   root no host). É feature (admin-only), mas merece: confirmar role admin no
   save, gravar hook em AuditLog, e rodar com timeout (`Timeout.timeout` ou
   `timeout(1)` do coreutils) — hoje um hook pendurado trava o job de deploy
   para sempre.
7. **`service_scale` lê-modifica-escreve sem retry.** Entre `service(id)` e o
   update, outro ator (outro admin, o próprio swarm) pode bump a Version →
   `Docker API error 409`. Retry 1x com version fresca resolve.
8. **Threads órfãs no `ttyd_ws`**: `up.join; down.join` — se o browser some sem
   FIN (celular fecha tampa), o pump down segue vivo até o ttyd morrer. `--once`
   limita o dano; um `IO.select` com timeout de inatividade (ex.: 8h) fecharia
   sessões zumbis que seguram thread Puma. Com `RAILS_MAX_THREADS=16` e
   single-worker, 16 terminais zumbis = app inteiro indisponível.
   Relacionado: subir `WEB_CONCURRENCY=2` no stack yml é hedge barato.
9. **SQLite + Solid Queue no mesmo arquivo em produção** funciona (WAL), mas
   `MetricsJob` a cada 30s + `HostMetric.delete_all` competem com requests.
   Se o painel crescer (multi-node, edge), migrar para PostgreSQL da stack
   (`postgres-cluster` já existe no host). Baixo esforço, adiável.

### Baixa

10. **`DashboardController` agora dispara services/nodes mesmo sem swarm**
    (rescue nil) — desperdício mínimo; aceitável pela simplicidade.
11. **`parse_ls_output`** regex frágil para nomes com espaços/newline; usar
    `ls -la --time-style=+%s` ou `find -printf` quando disponível. Edge case
    cosmético.
12. **`container_stats_snapshot`** com `stream: false` demora ~1s por design da
    API (amostra 2x). Para tabela de containers, usar `/containers/json` +
    one-shot `stats?stream=0&one-shot=1` (API ≥1.41) corta pela metade.
13. **Login 700ms** = bcrypt (ok, segurança) + GC 185ms. Nada a fazer.
14. **`force_ssl` comentado** — Traefik termina TLS; ligar
    `config.assume_ssl = true` + `force_ssl = true` daria cookies `Secure` e
    HSTS de graça (verificar que o healthcheck `/up` interno continua http).

## 3. Gap de features vs concorrentes (2026)

Referência: Portainer BE, Komodo (Rust, Periphery agents), Dockge, Arcane (Go,
GitOps embutido), Rancher (k8s). Fontes no fim.

**Já temos (paridade ou melhor):**
containers/images/volumes/networks CRUD · stacks swarm · services
(scale/rollback/update image/resources/logging) · configs+secrets ·
GitOps (poll, webhook, drift 3-way, revisões, CI gate, hooks pre/post) ·
terminal ttyd rápido · file browser + download/upload · métricas host + alertas ·
RBAC 3 níveis + teams · audit log · registries · multi-env (unix/tcp) ·
aba Security (portas, fail2ban, firewall, integridade, mapa) — **diferencial
que nenhum concorrente tem embutido**.

**Gaps, por impacto:**

| Gap | Quem tem | Custo | Nota |
|---|---|---|---|
| **Suporte Kubernetes (k3s/k8s)** | Portainer, Rancher | Alto | Specs criadas — é o divisor Portainer vs resto |
| **Edge agents / multi-host real** | Portainer Edge, Komodo Periphery | Alto | tcp:// sem TLS não conta; spec criada |
| **Podman** | Portainer (parcial) | Baixo–médio | API compatível; spec criada |
| **Update-check de imagens (shepherd/watchtower-like)** | Komodo, Arcane, dockcheck | Baixo | comparar digest local vs registry, badge "update available" + botão |
| **Web editor de compose com validação/diff antes do deploy** | Dockge (líder), Komodo | Baixo | temos textarea; falta `docker compose config` dry-run + diff |
| **Templates / app store (1-click deploys)** | Portainer, CasaOS, Runtipi | Médio | JSON de templates + form de env |
| **Terminal multi-tab / exec no host** | Portainer BE | Baixo | ttyd já suporta; UI |
| **Container stats live por container (sparklines na lista)** | Arcane, Portainer | Médio | já temos stats channel; falta agregação leve |
| **Backup/restore de volumes agendado** | Nautical, Duplicati integração | Médio | temos browse/upload; falta job agendado + retenção |
| **OIDC/SSO** | Portainer BE, Komodo | Médio | Devise não é usado aqui (auth custom Rails 8); omniauth_openid_connect resolve |
| **Notificações externas (Telegram/Slack/webhook out)** | Komodo, diun | Baixo | Alert existe; falta canal de saída |
| **Image build from Git (CI-lite)** | Komodo (forte) | Alto | fora de escopo por ora — GitLab CI já cobre |
| **Prune agendado com política** | Komodo | Baixo | DockerSystemPruneJob existe; falta agenda configurável na UI |

**Recomendação de sequência (custo/benefício):**
1. Update-check de imagens (baixo custo, uso diário)
2. Editor compose com dry-run+diff (baixo)
3. Notificações Telegram/Slack (baixo)
4. Podman runtime (spec pronta — abre laptop/dev e hosts sem daemon root)
5. Edge agents (spec pronta — desbloqueia multi-host de verdade)
6. k3s → k8s (specs prontas — aposta estratégica)

## 4. Specs criadas nesta sessão

- `docs/specs/feature-runtime-abstraction-podman.md`
- `docs/specs/feature-kubernetes-k3s.md`
- `docs/specs/feature-kubernetes-k8s-multicluster.md`
- `docs/specs/feature-edge-compute.md`

Fontes da análise de mercado:
[Botmonster — Komodo vs Portainer vs Dockge 2026](https://botmonster.com/self-hosting/komodo-vs-portainer-vs-dockge-2026-homelab-decision-guide/) ·
[Bitdoze — Portainer alternatives 2026](https://www.bitdoze.com/portainer-alternatives/) ·
[NetGuardia — Container UIs ranked](https://netguardia.com/privacy/self-hosting/portainer-vs-dockge-vs-komodo-container-management-uis-ranked/) ·
[Better Stack — Docker UI alternatives](https://betterstack.com/community/comparisons/docker-ui-alternative/) ·
[VirtualizationHowto — Arcane](https://www.virtualizationhowto.com/2025/12/why-arcane-might-be-the-next-big-docker-ui-for-the-home-lab/) ·
[OneUptime — Portainer vs Dockge](https://oneuptime.com/blog/post/2026-03-20-portainer-vs-dockge/view)
