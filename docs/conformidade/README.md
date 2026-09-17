# ⚠️ PENDENTE · URGENTE — Conformidade para APIs públicas (VPS inteira)

> Levantamento de 2026-09-17, feito só com leitura: nada foi alterado.
> Escopo: **a VPS redhusky-lab-01 inteira**, não um projeto só. A RedHusky quer consumir várias APIs
> públicas (Senatran/Serpro, DataJud CNJ, Portal da Transparência etc.), e o credenciamento avalia a
> **organização** e a infraestrutura onde as aplicações rodam.
> O caso mais exigente hoje é a **Portaria SENATRAN nº 139/2025**, pedida pelo CN Route. Ela serve de
> régua: o que passa nela passa na maioria das outras.
>
> Texto integral da portaria: [`portaria-senatran-139-2025.txt`](portaria-senatran-139-2025.txt)
> (extraído do PDF oficial do gov.br).

---

## 1. Resumo executivo

1. **A portaria não manda "criptografar o disco" com essas palavras.** Ela exige **um** destes (art. 22):
   - nível **satisfatório** no formulário de maturidade em segurança da informação da Senatran;
   - **ou** um certificado **ABNT NBR ISO/IEC 27001** com escopo sobre **toda a organização**, incluindo
     as aplicações integradas.

   Criptografia em repouso, backup cifrado, log de acesso e resposta a incidente entram pela nota do
   formulário. Sem elas a nota não chega a 4.
2. **Nota mínima:**
   - Dado pessoal comum: **≥ 4 de 5**.
   - Dado pessoal **sensível**: **5 de 5**.
   - Nota 3 (ou 4 com sensível) conta como "regular". Vira pendência com **30 dias** para corrigir (art. 32).
   - Abaixo disso é **indeferimento** (art. 34).
3. **As respostas do formulário valem como declaração, sob responsabilidade civil e penal** (art. 23 §3).
   Não dá para marcar "sim" no que ainda não existe. Por isso a lista da seção 4 precisa estar pronta
   **antes** de preencher.
4. **Fiscalização:**
   - Pode haver auditoria **remota** e **presencial** (arts. 55-58).
   - Todo sistema que usa dado da Senatran precisa oferecer um **módulo de perfil de acesso de auditoria
     (somente leitura)**, conforme o manual técnico.
   - Esse módulo não existe hoje em nenhum projeto.
5. **Há 9 lacunas graves e comuns à VPS** (seção 4.1). Nenhuma pede separar o cluster Postgres. Todas se
   resolvem no host e no app, com o banco como está.

---

## 2. Requisitos da Portaria 139/2025, artigo por artigo

Legenda: ✅ atende · ❌ não atende · 🔍 a verificar/decidir · 📄 documento a produzir

### 2.1 Requisitos para se credenciar (art. 22)

| Requisito | Status | Observação |
|---|---|---|
| CNPJ ativo | ✅ | 45.120.868/0001-63 (Welinton dos Reis Gonçalves Consultoria em TI Ltda) |
| Certificado e-CNPJ ICP-Brasil | 🔍 | confirmar validade. Vencer o certificado **bloqueia** o acesso (art. 61), com 30 dias para regularizar |
| Responsável técnico com nível superior | 🔍 | nomear e juntar diploma |
| Canal permanente de atendimento ao titular | 🔍 | hoje é o e-mail `privacidade@redhusky.com.br` (página `legal/senatran` do cnroute). Faltam prazo de resposta e registro dos pedidos |
| Maturidade satisfatória (art. 23) **ou** ISO 27001 da organização | ❌ | seção 4 |
| Contrato com o Serpro | ❌ | assinar depois do deferimento |
| Contrato com um GCC (gestor de consentimento credenciado) | ❌ | escolher o GCC. O consentimento do titular passa por ele |

### 2.2 Formulário de maturidade (art. 23)

- Formulário eletrônico com nota de 1 a 5.
- Sem dado sensível: ≤2 insatisfatório, 3 regular, ≥4 satisfatório.
- Com dado sensível: ≤3 insatisfatório, 4 regular, 5 satisfatório.
- §3: as respostas são declaração verdadeira, com responsabilidade civil e penal.
- §5/§6: o certificado ISO 27001 dispensa o formulário.
- 🔍 **As perguntas do formulário não são públicas no texto da portaria.** Pedir ao Serpro/Senatran ou
  obter no início do processo, e fazer um ensaio antes de enviar.

### 2.3 Documentos exigidos (art. 26 §1)

| Documento | Status |
|---|---|
| Contrato social e alterações | 🔍 juntar |
| RG/CPF dos representantes legais e do responsável técnico | 🔍 juntar |
| Comprovante de endereço da empresa | 🔍 juntar |
| Contatos (e-mail/telefone) do representante e do responsável técnico | 🔍 juntar |
| Identificação do Encarregado (DPO), exigida quando há dado restrito | 📄 formalizar a nomeação |
| Descrição da atividade e da finalidade do uso dos dados | 📄 |
| Política de Privacidade e Termos de Uso publicados | 🔍 o cnroute tem `legal/senatran`. Falta uma política da organização, que cubra todos os produtos |
| Termo de Compromisso de Manutenção de Sigilo (assinatura eletrônica avançada/qualificada) | 📄 assinar com o e-CNPJ |
| Certidões CEIS, TCU e improbidade | 🔍 emitir perto da data do pedido (validade curta) |

### 2.4 Análise e prazos (arts. 30-37)

- Parecer preliminar em até **60 dias**.
- Pendência (inclusive maturidade "regular"): **30 dias** para corrigir (art. 32).
- Maturidade insatisfatória: indeferimento (art. 34).
- Depois do deferimento: **60 dias** para contratar Serpro e GCC (art. 37).

### 2.5 Operação depois de credenciado

| Artigo | Exigência | Status |
|---|---|---|
| 40 | O credenciamento não vence, mas **12 meses sem consulta** pode levar à revogação | 🔍 |
| 44-45 | Consentimento com conteúdo mínimo. O titular vê o histórico de consultas | ❌ não implementado (depende do GCC) |
| 46 | Canal e comunicação de incidente | ❌ falta plano escrito |
| 51 | Avaliação de risco / RIPD, com matriz de risco | ❌ 📄 |
| 55-58 | Monitoramento, auditoria remota (videochamada, documentos, **módulo de auditoria só-leitura**) e presencial | ❌ módulo inexistente |
| 21 | Manual técnico da Senatran (especifica o módulo de auditoria e a integração) | 🔍 **não lido ainda**: obter |
| 66 | Autorizações antigas caem 60 dias após a publicação da lista de GCCs | 🔍 acompanhar |

### 2.6 Sanções (arts. 59-63)

- Limitação do volume de consultas.
- **Bloqueio**, inclusive por certificado vencido (30 dias para regularizar).
- Suspensão.
- **Revogação**, com impedimento de até **2 anos** para novo credenciamento.

Uma falha grave em um projeto derruba o credenciamento da **empresa**, e com ele todos os produtos que
usam a API.

---

## 3. Outras APIs públicas: o que muda

A Senatran é a régua mais alta. Para as demais, a exigência é menor, mas o mesmo alicerce serve:

| API | O que ela costuma exigir | Situação |
|---|---|---|
| Senatran / Serpro (Consulta Online) | Portaria 139/2025 inteira (acima) | pedido pelo cnroute |
| DataJud (CNJ) | chave pública de API e termo de uso. Os dados vêm de processos, e parte tem dado pessoal | já usado (HuskyOS) |
| Portal da Transparência (CGU) | chave por e-mail e limite de requisições. Dado público, mas com CPF mascarado | já usado |
| Conecta gov.br / outras APIs do Serpro | contrato e termo de uso próprios. Muitas pedem e-CNPJ e mTLS | 🔍 mapear quando houver pedido |

**Regra da casa (proposta):** toda nova API pública ganha uma linha nesta tabela antes da integração.
A linha registra o termo de uso, a base legal LGPD, que dado pessoal entra e o prazo de retenção.

**Independente de API, a LGPD já exige tudo o que está abaixo** (art. 46: "medidas de segurança,
técnicas e administrativas aptas a proteger os dados pessoais"). Não é custo só do credenciamento.

---

## 4. Estado atual da VPS (medido em 2026-09-17)

Host: redhusky-lab-01 (167.86.110.111, Contabo). Um nó Swarm (leader), 39 serviços, 63 diretórios em
`~/docker`, Postgres 17 com 34 bancos (≈14 GB). Disco único `sda` de 400 G, 220 G usados.

### 4.1 Lacunas graves (bloqueiam nota ≥ 4)

| # | Lacuna | Evidência | Correção proposta |
|---|---|---|---|
| G1 | **Disco sem criptografia em repouso** | `sda1` ext4 direto, sem LUKS. O volume `postgres_postgres_master_data` (16 G) fica em texto claro | Contêiner LUKS2 para os volumes do Postgres e o diretório de segredos, com destrave automático Clevis+Tang (seção 5, camada 2) |
| G2 | **Swap sem criptografia** | `/swapfile` 4 G, 1,9 G em uso: página de memória do Postgres/Rails vai ao disco em claro | swap cifrado com chave aleatória a cada boot (`crypttab` com `/dev/urandom`) |
| G3 | **Backup físico (WAL-G) sem criptografia do lado da empresa** | imagem `redhusky-postgres-walg:pg17-v4` sem `WALG_LIBSODIUM_KEY`/`WALG_PGP_KEY` | `WALG_LIBSODIUM_KEY` com a chave fora do disco da VPS |
| G4 | **Dumps lógicos diários em claro no R2** | `redhusky-backup/backup-diario.sh` (cron 04:00) cifra com gpg só o tar de segredos | passar todo dump por `gpg --symmetric` (ou `age`) antes do upload |
| G5 | **Chaves no mesmo disco dos dados** | 21 `.env` em `~/docker` com `RAILS_MASTER_KEY`, `SECRET_KEY_BASE`, `LOCKBOX_MASTER_KEY`, senha do banco. **21 de 23 sem permissão 600** | curto prazo: `chmod 600`. Depois: segredos dentro do LUKS ou em Docker secrets |
| G6 | **Postgres sem TLS** | `ssl off` no postgres-master. O tráfego app→pgbouncer→postgres corre em overlay sem cifra | `ssl on` com certificado interno + `sslmode=require` nos apps, ou overlay `encrypted` |
| G7 | **Overlays sem criptografia** | redes `postgres-cluster` e `routing` com a opção `encrypted` vazia | recriar com `--opt encrypted` (IPsec). Nó único, então o ganho real é pequeno: G6 resolve melhor |
| G8 | **Sem log de acesso a dado pessoal nem módulo de auditoria** | nenhum projeto registra quem consultou qual CPF/placa e quando | tabela append-only de consultas por app + perfil "auditor" só-leitura (art. 57) |
| G9 | **Sem documentação de governança** | não há política de segurança, plano de incidente, RIPD, inventário de dados nem registro de operações (LGPD art. 37) | produzir os 📄 da seção 5, camada 4 |

### 4.2 Lacunas médias

| # | Lacuna | Evidência | Correção |
|---|---|---|---|
| M1 | Portas publicadas sem regra de DROP no `DOCKER-USER` | `DOCKER-USER` barra 5432, 6432, 5436, 9001, 8082, 8404, 11434, 6380, 2377, 7946. **Ficam fora:** 20128 (9router), 4416 (huskygate), 50051 (stargate broker gRPC), 15692 (métricas RabbitMQ), 1433 (MSSQL via Traefik), 5672 (AMQP via Traefik) | 🔍 testar de **fora** da VPS (o teste local não prova exposição). O que não precisa ser público entra no DROP; o que precisa ganha TLS e autenticação |
| M2 | 4 serviços com imagem `:latest` | `postgres_pgadmin`, `evolution_evolution-api`, `9router_headroom`, `seaweedfs_seaweedfs` | fixar versão: regra da casa e requisito de gestão de mudança |
| M3 | pgAdmin exposto na internet | `pgadmin.pgdb.redhusky.com.br` via Traefik: painel com acesso a todos os bancos | restringir por IP/VPN ou autenticação extra no Traefik |
| M4 | Tokens git em texto claro nas URLs de remote | CRT-1 da auditoria de 2026-07-06, ainda aberto (visto de novo hoje no husky-core) | credential helper + rotação dos tokens |
| M5 | Swarm sem autolock | `AutoLockManagers=false`: chaves do Raft (segredos do Swarm) ficam em claro no disco | `docker swarm update --autolock=true`. Exige destravar no boot, então casar com a solução de G1 |
| M6 | Filtro de log do Rails incompleto | ex. cnroute: `filter_parameter_logging` sem `cpf`, `cnh`, `placa`, `renavam`, `telefone` | acrescentar em todos os apps que tocam dado pessoal (hoje, nos logs de 72 h do cnroute, 0 ocorrências de `"cpf"`) |
| M7 | Retenção de logs sem política | journald com 4,0 G, logs Docker `json-file` com 1,7 G, sem prazo definido | definir prazo (ex.: 6 meses para log de acesso, Marco Civil art. 15) e rotação |

### 4.3 O que já está bom (usar como evidência no formulário)

- SSH só com chave. `sshd -T`: `passwordauthentication no`, `permitrootlogin without-password`. fail2ban ativo.
- Hardening de 2026-07-01 aplicado: Ollama interno, `DOCKER-USER` barrando bancos e painéis.
- TLS público via Traefik + Let's Encrypt em todos os domínios.
- **R2 cifra em repouso por padrão** com AES-256-GCM e chave gerenciada pela Cloudflare
  ([fonte](https://developers.cloudflare.com/r2/reference/data-security/)).
  - **Limite do argumento:** protege contra a mídia física do provedor, não contra vazamento da credencial
    do bucket.
  - Não substitui G3/G4.
  - No texto formal escrever "AES-256-GCM", não "criptografia militar".
- Lockbox já em uso para segredos OTP (cnroute, entre outros) e para `Account#integrations`.
- 2FA TOTP (devise-two-factor) na stack padrão.
- Backup diário + WAL contínuo fora do host (R2).
- Painel de segurança no orchestration (brute-force SSH, fail2ban, firewall), atualizado a cada 5 min.

### 4.4 Situação específica do cnroute (primeiro a pedir credenciamento)

- A integração com a Senatran **não existe ainda**: não há chamada à API nem consentimento.
- Tabela global `drivers` (schema público, fora do Apartment): `cpf`, `cnh`, `cnh_category`,
  `cnh_expires_at`, `name` e `phone` em **texto claro**. Hoje são 17 motoristas: 17 com CNH, 1 com CPF.
- `force_ssl`/`assume_ssl` comentados em `production.rb`. O Traefik termina o TLS, mas o `assume_ssl` deveria
  estar ligado para cookie `secure`.
- A página `legal/senatran` declara TLS 1.2+, RBAC e e-CNPJ. **Não declara criptografia em repouso**:
  manter assim até G1-G4 estarem prontos.
- Retenção declarada: vínculo + 5 anos. Falta o job que apaga ao vencer.

---

## 5. Plano de correção por camadas (sem separar o banco)

A ordem vai do mais barato e de maior efeito para o mais caro. Cada camada é independente.

### Camada 1 — Aplicação (dias, sem downtime)
1. Lockbox + `blind_index` nos campos pessoais que vêm ou vão para a API: CPF, CNH, placa, RENAVAM e o
   resultado da consulta. Começa pelo `Driver` do cnroute.
2. Tabela append-only `consultas_api` por app: quem, quando, qual titular (hash), finalidade, id do
   consentimento, resposta resumida.
3. Perfil `auditor` só-leitura (art. 57): vê consultas, consentimentos e trilha de acesso, e não edita nada.
4. Filtro de log com `cpf`, `cnh`, `placa`, `renavam`, `telefone` em todos os apps.
5. `assume_ssl = true` nos apps atrás do Traefik.

### Camada 2 — Host (1 janela de manutenção)
1. **G2** swap cifrado com chave efêmera (nenhum dado se perde, só `swapoff`/`swapon`).
2. **G5** `chmod 600` em todos os `.env` (imediato, sem risco).
3. **G3** `WALG_LIBSODIUM_KEY` no postgres-master. **Fazer backup completo novo logo depois**: backups
   antigos continuam legíveis só sem a chave.
4. **G4** gpg/age nos dumps do `backup-diario.sh`.
5. **G1** LUKS2 sobre um arquivo-contêiner (ou partição nova) montado onde ficam
   `/var/lib/docker/volumes/postgres_*` e os segredos.
   - Migração: parar a stack postgres → copiar os volumes → montar → subir. Downtime estimado de
     15-30 min para 16 G, a medir num ensaio no postgres-development primeiro.
   - **Destrave automático com Clevis + Tang.** Sem isso, todo reboot deixa os 34 bancos fora do ar até
     alguém digitar a senha.
   - O Tang precisa ficar **fora** desta VPS.
   - 🔍 **Decisão pendente: onde hospedar o Tang** (outra VPS barata, o PC do escritório com túnel, ou
     destrave manual aceito como procedimento).
6. **M5** autolock do Swarm, casado com o mesmo mecanismo de destrave.
7. **Chaves fora do disco:** as chaves do libsodium, do gpg e do LUKS (cabeçalho + passphrase de
   recuperação) ficam num cofre fora da VPS, com cópia offline.

### Camada 3 — Rede (horas)
1. **G6** `ssl on` no Postgres + `sslmode=require` nos apps, conexão a conexão (pgbouncer primeiro).
2. **M1** testar as portas de fora e fechar o que não precisa ser público.
3. **M3** pgAdmin atrás de allowlist/VPN.
4. mTLS com o e-CNPJ na chamada ao Serpro, quando a integração existir (o certificado é **da empresa**,
   não "fornecido pelo Serpro").

### Camada 4 — Governança (documentos 📄, semanas)
1. Política de Segurança da Informação da organização (curta, verdadeira, assinada).
2. Inventário de dados pessoais e registro de operações de tratamento (LGPD art. 37), por produto.
3. RIPD com matriz de risco (art. 51 da portaria / LGPD art. 38).
4. Plano de resposta a incidente: quem avisa, em quanto tempo, a ANPD (Res. CD/ANPD 15/2024: 3 dias
   úteis) e a Senatran (art. 46).
5. Procedimento de backup **com teste de restauração registrado** (data, tempo, resultado).
6. Gestão de acesso: quem tem root/SSH/pgAdmin, revisão trimestral, desligamento.
7. Gestão de mudança: versão fixa de imagem (M2), deploy com commit rastreável (já existe).
8. Nomeação formal do Encarregado (DPO) e do responsável técnico.
9. Termo de sigilo assinado com e-CNPJ.

---

## 6. Sobre o guia LUKS recebido (avaliação)

Aproveitado: LUKS2 + AES-XTS para os volumes. Problemas encontrados:

- **Destrave manual no boot** derruba os 34 bancos a cada reboot até alguém digitar a senha. Precisa de
  Clevis/Tang ou de procedimento aceito.
- **Ignora swap, backups (WAL-G/dumps), réplicas (postgres-read, analytics) e logs.** O dado sai do
  contêiner cifrado por esses caminhos.
- Não existe TDE no Postgres comunitário. "Criptografar o banco" aqui significa disco (LUKS) + campo (Lockbox).
- O certificado é o **e-CNPJ do cliente**, não "fornecido pelo SERPRO".
- "O auditor aceita" não tem fonte. A portaria avalia por formulário/ISO e não prescreve ferramenta.

---

## 7. Checklist de execução (ordem sugerida)

- [ ] **Hoje, sem risco:** G5 `chmod 600` nos `.env` · M6 filtro de log · M2 fixar as 4 imagens `:latest`
- [ ] Obter o **formulário de maturidade** e o **manual técnico** (art. 21) com Serpro/Senatran
- [ ] Decidir onde fica o **servidor Tang**
- [ ] Camada 1 no cnroute (Lockbox em `drivers`, `consultas_api`, perfil auditor)
- [ ] G2 swap cifrado
- [ ] G3/G4 backups cifrados + teste de restauração registrado
- [ ] M1 teste externo de portas + ajuste do `DOCKER-USER`
- [ ] G6 TLS no Postgres
- [ ] G1 LUKS + Clevis/Tang (ensaio no postgres-development antes)
- [ ] M5 autolock do Swarm
- [ ] M3 pgAdmin restrito · M4 tokens git rotacionados
- [ ] Camada 4: política, inventário, RIPD, plano de incidente, nomeações, termo de sigilo
- [ ] Ensaio do formulário: meta 5/5 se houver dado sensível, 4/5 no mínimo
- [ ] Juntar documentos do art. 26 e protocolar
- [ ] Avaliar ISO 27001 no médio prazo: dispensa o formulário e vale para qualquer API

## Fontes

- [Portaria SENATRAN nº 139/2025 (PDF gov.br)](https://www.gov.br/transportes/pt-br/assuntos/transito/arquivos-senatran/portarias/2025/Portaria1392025.pdf)
- [Serpro: aviso sobre o acesso a dados da Senatran](https://centraldeajuda.serpro.gov.br/duvidas/pt/avisos/senatranacessodados/)
- [Cloudflare R2: data security](https://developers.cloudflare.com/r2/reference/data-security/)
- LGPD (Lei 13.709/2018), arts. 37, 38, 46 e 48 · Resolução CD/ANPD nº 15/2024 (comunicação de incidente)
