# Feature — Skeletons de loading e fim da tela congelada

> Status: 🚧 em andamento · Iniciado 2026-09-01

## Problema

Várias telas do Orchestration fazem I/O pesado (socket do Docker, SSH, HTTPS
externo) **antes** de renderizar. O usuário clica e a tela fica parada, sem
nenhum sinal de que algo está acontecendo — a plataforma parece lenta mesmo
quando o trabalho em si é rápido.

Três causas distintas, com consertos distintos:

1. **Toda requisição pagava uma chamada ao socket do Docker**, inclusive as
   páginas que só leem o banco.
2. **A navegação não dava feedback nenhum** — o layout desativa o cache do
   Turbo globalmente, então a página antiga fica na tela até a nova chegar.
3. **~20 telas bloqueiam em I/O** antes do primeiro byte.

## Decisões

### As 83 páginas ficam cobertas, mas não todas do mesmo jeito

Skeleton de conteúdo nas telas que fazem I/O; barra de progresso nas que já
respondem em milissegundos. Transformar uma tela instantânea em turbo-frame
lazy adiciona um roundtrip — deixaria ela **mais lenta**, não mais rápida. A
sensação de plataforma única vem dos itens 1 e 2, que valem para todas.

### O padrão já existia no repo

Oito telas já usavam `<turbo-frame src=…>` com um bloco `animate-pulse` escrito
à mão dentro. Note que **o helper `turbo_frame_tag` e `loading: :lazy` não são
usados em lugar nenhum** — o padrão da casa é a tag HTML crua. O trabalho foi
estender esse padrão, não inventar um novo.

## O que foi feito

### 1. Cache do `DockerClient#capabilities`

`ApplicationController#runtime_capabilities` alimenta a sidebar e roda em toda
requisição; `SwarmGuard` lê de novo como `before_action`. Os dois caem em
`DockerClient#capabilities`, que chamava `/info` no socket **toda vez** — o
comentário no código prometia "cached 10min", mas só `runtime` era cacheado, e
`@capabilities ||=` é memoização por request.

Com o daemon lento ou fora do ar, isso era um timeout de socket antes de
qualquer byte sair — skeleton nenhum resolveria, porque a página nem começava a
renderizar. O conserto é um `Rails.cache.fetch` na função compartilhada, então
vale para os dois chamadores de uma vez.

**Teto conhecido:** TTL de 60s, então entrar ou sair de um swarm leva até um
minuto para refletir na navegação. Se incomodar, invalidar a chave nas mutações
de swarm.

### 2. Barra de progresso do Turbo

Não havia nenhuma customização (`grep turbo-progress-bar` → zero), então valia a
barra azul fina padrão, depois de 500ms de espera. Agora ela é da cor da marca,
3px, com glow para aparecer nos quatro temas, e o delay caiu para 100ms.

### 3. `Ui::SkeletonComponent`

O skeleton de tabela estava copiado e colado em sete telas, variando só a
largura das colunas e a contagem de linhas; o de stat card, em duas.

```ruby
render Ui::SkeletonComponent.new(:table, columns: [ :check, "w-40", "w-12", :actions ], rows: 8)
render Ui::SkeletonComponent.new(:stats, count: 5)
render Ui::SkeletonComponent.new(:cards, count: 6)
render Ui::SkeletonComponent.new(:toolbar)
render Ui::SkeletonComponent.new(:detail)
```

O `:table` recebe uma **especificação de colunas**, não uma contagem: o sentido
do skeleton é que o conteúdo real caia no mesmo lugar que o placeholder
ocupava. Cada entrada é uma classe de largura do Tailwind, ou `:check` para o
checkbox da primeira coluna, ou `:actions` para o grupo de botões da última.

Acessibilidade: `aria-busy="true"` no wrapper, `aria-hidden` nas barras
decorativas e um `sr-only` "Carregando…". Antes disso não havia um único
`aria-busy` no app.

Não confundir com os `animate-pulse` de `stacks/rows.html.erb`,
`git_stacks/index.html.erb` e `cloudflare_dns/index.html.erb`: ali é indicador
de status, não de carregamento.

### 4. Conversão das telas que bloqueiam

Cada conversão separa a ação em duas: `index` vira a casca (título, estado
vazio, e o turbo-frame com o skeleton) e `rows` faz o I/O.

**Armadilha a replicar** (está comentada em `containers_controller.rb`): quando
os links de filtro/paginação dentro de `rows` apontam de volta para `index`
— para a URL refletir o estado —, `index` precisa de
`rows if turbo_frame_request?`, senão aninha um turbo-frame dentro do próprio
frame sendo renavegado e o fetch seguinte nunca dispara. Telas sem filtro (como
`environments`) não precisam disso.

| Tela | Custo antes | Status |
|---|---|---|
| `environments#index` | **7 chamadas de socket por ambiente, em série** — 5 ambientes = 35 chamadas em fila. A ação mais lenta do app. | ✅ piloto |
| `kube/fleet#index` | 4 chamadas × N clusters; cluster offline segura a página 5s | ✅ |
| `security#index` | varredura de `/proc` + 2 chamadas de socket | ✅ |
| `cloudflare_dns#index` | HTTPS externo + 2 chamadas de socket, em série | ✅ |
| `vps_files#index` | handshake SSH | ✅ (sem frame — ver abaixo) |
| `seaweedfs#index` | 3 chamadas HTTP em série | ✅ |
| `dashboard#index` | 7 chamadas Docker (é a rota raiz) | 📋 |
| `swarm/{topology,dashboard,policies,nodes}#index`, `swarm/services#show` | 1–4 em série cada | ✅ |
| `kube/*#index` (7 telas) | 2–4 em série cada | ✅ |
| `containers#{show,files}`, `images#show`, `configs#index` | 1–2 cada | 📋 |
| `volumes#browse` | pode **criar e subir um container auxiliar** antes de responder | 📋 |

### `vps_files#index` não virou turbo-frame

O HTML dessa tela nunca usou o resultado do SFTP: `vps_file_browser_controller.js`
busca a **mesma ação em JSON** ao conectar e desenha a listagem sozinho. O
handshake SSH no caminho HTML só atrasava o primeiro byte de uma resposta que
jogava o resultado fora. O conserto foi tirar o I/O do `format.html` (o
`format.json` continua igual) e pôr o skeleton dentro do alvo `list`, que o
Stimulus substitui inteiro no primeiro render. Um `rows` aqui seria um
roundtrip a mais para devolver nada.

### `card: false` e `grid:` no `Ui::SkeletonComponent`

Duas opções novas, cada uma por um motivo concreto: `security` monta os stat
cards num grid de 4 colunas (o do dashboard é de 5) e o skeleton do `vps_files`
mora **dentro** de um card que já existe — um segundo box com borda aninhado no
primeiro é exatamente o ruído de layout que o skeleton deveria evitar.

### Três casos que não couberam no molde do piloto

`swarm/topology#index` — o Stimulus `metrics-refresh` recarrega o frame
limpando o `src` e reapontando para `window.location.href`, ou seja, bate no
`index` com header `Turbo-Frame`. Sem `rows if turbo_frame_request?` cada
auto-refresh trocaria a topologia por um skeleton que nunca resolve.

`kube/*#index` — o seletor de namespace precisa da lista de namespaces (mais
uma chamada), então mora **dentro** do frame; mas ele posta de volta no
`index`, e o namespace aparece no `page_subtitle`, que está **fora** do frame.
Com `target="_top"` no frame o submit continua sendo navegação de página
inteira: URL e subtítulo seguem coerentes e o skeleton reaparece na troca.

`swarm/services#show` — o título da página era o nome do serviço, que só existe
depois do I/O. A casca passa a mostrar "Serviço Swarm" + o ID da URL; o nome
real continua no herói, dentro do frame. E o `rescue` do `show` não pode mais
redirecionar (a resposta cairia dentro de um frame que não existe no index dos
serviços): `#body` renderiza o erro no lugar, com um link `_top` de volta.

## Verificação

- `test/components/ui/skeleton_component_test.rb` — uma célula de cabeçalho e
  uma de corpo por coluna, por linha; a largura chega na barra; `aria-busy`
  presente; variante desconhecida cai em `:table` em vez de renderizar nada.
- `test/controllers/environments_controller_test.rb` — **`index` não pode tocar
  o socket**: o teste roda com um cliente que levanta `ConnectionError` e ainda
  espera `200` com o frame e o `aria-busy`. Se alguém mover o probing de volta
  para o `index`, esse teste quebra.
- `test/controllers/{security,seaweedfs,vps_files,cloudflare_dns}_controller_test.rb`
  e `test/controllers/kube/fleet_controller_test.rb` — o mesmo par por tela: o
  `index` responde 200 com a dependência externa levantando erro, e o `rows`
  responde 200 tanto no caminho feliz quanto com ela morta.
- Manual: com throttling de rede no DevTools, a tela mostra o skeleton e nunca
  um branco, e nada salta de lugar na troca.
