# Spec — File browser: upload/edit/delete (v1.0)

**Status:** ✅ implementado (2026-07-06) — upload via Docker archive API,
delete/mkdir/rename via exec, tudo operator+ e auditado em `audit_logs`.
Editor inline de texto (v1.0 original pedia) não entrou — baixo uso real
frente ao custo, upload de arquivo editado localmente cobre o caso.

## Gatilhos

1. Precisar trocar um arquivo de config num container sem rebuild ≥ 1×
   (hotfix de emergência).
2. RBAC enforcement (feature-rbac-enforcement) **shipped primeiro** —
   escrita em filesystem de container sem roles é RCE dado a qualquer
   login. Dependência dura, não sugestão.

## Desenho

- Reusa a base read-only (`/containers/:id/files`, `exec_run_output` +
  `container_archive_get`):
  - **Upload**: `PUT /containers/:id/archive?path=` da Docker API (tar
    com o arquivo) — API nativa, sem exec.
  - **Editor inline**: arquivos texto < 1MB — GET do conteúdo (já
    existe), textarea com monospace, salvar = tar + PUT archive. Sem
    Monaco (peso não paga; é editor de emergência, não IDE).
  - **Delete/mkdir/rename**: `exec` (`rm`/`mkdir`/`mv`) — container
    precisa ter busybox/coreutils; erro do exec aparece pro usuário.
- Toda escrita: role **operator+**, entrada em `audit_entries`
  (user, container, path, ação) e aviso claro "mudança morre com o
  container — persistência de verdade é volume/imagem".
- **Fora**: upload de diretório recursivo, chmod/chown UI.

## Custo

1 sessão depois do RBAC.
