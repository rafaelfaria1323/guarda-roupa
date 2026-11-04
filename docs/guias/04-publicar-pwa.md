# Guia 04 — Publicar a PWA

Estado (2026-11-04): **automático**. O workflow [`PWA`](../../.github/workflows/pwa.yml) faz a build com [`tool/web/build_pwa.sh`](../../tool/web/build_pwa.sh) e publica-a no Cloudflare Pages (plano Free), no projeto `guarda-roupa`. Corre depois de cada merge na `main` com a CI verde, ou à mão em Actions › PWA › Run workflow. Não corre nos PRs.

Endereço: `https://guarda-roupa.pages.dev`. Se o nome já estiver ocupado no Cloudflare, o endereço real aparece no resumo do workflow.

## 1. Uma vez só: a conta e os secrets (tu)

1. Entrar ou criar conta em https://dash.cloudflare.com/ (plano Free).
2. Copiar o **Account ID**: em Workers & Pages, na coluna da direita (ou no menu da conta › Account ID).
3. Criar um token: My Profile › API Tokens › **Create Token** › **Create Custom Token**.
   - Permissions: **Account** › **Cloudflare Pages** › **Edit**.
   - Account Resources: só a tua conta.
   - Continue to summary › Create Token. O token só é mostrado uma vez.
4. No GitHub, em Settings › Secrets and variables › Actions › New repository secret, criar:
   - `CLOUDFLARE_API_TOKEN` com o token;
   - `CLOUDFLARE_ACCOUNT_ID` com o Account ID.
5. Correr o workflow à mão (Actions › PWA › Run workflow) ou esperar pelo próximo merge.

Não é preciso criar o projeto no dashboard: o workflow cria-o na primeira vez. Não colar os valores no chat nem no repositório.

## 2. O que o workflow faz

1. Build (`tool/web/build_pwa.sh`, também corre no Mac):
   - `dart run powersync:setup_web` (SQLite WASM e worker do PowerSync);
   - `tool/models/fetch_models.sh` (modelos e onnxruntime-web, com sha256/integridade confirmados);
   - `flutter build web --release --dart-define-from-file=config/public.json --no-web-resources-cdn` (só configuração pública; CanvasKit servido pela própria origem);
   - falha se encontrar algo com forma de chave secreta ou JWT, ou se faltar um ficheiro essencial.
2. Cria o projeto Pages se não existir e publica `build/web` com Wrangler (versão fixada no workflow) na branch de produção `main`.
3. Junta `https://<endereço>/**` às **Redirect URLs** do Supabase (Authentication › URL Configuration), com o `SUPABASE_ACCESS_TOKEN`. Só lê e escreve essa lista. Se o token não tiver permissão para a configuração do Auth, o job avisa e diz exatamente o que acrescentar à mão.

Os cabeçalhos estão em [`web/_headers`](../../web/_headers): `no-cache` para o index, o bootstrap e o service worker (cada versão nova chega logo), e um dia de cache para os modelos. Sem COOP/COEP: o COEP bloquearia as imagens das lojas nas inspirações; o PowerSync funciona sem eles e o onnxruntime corre numa só thread.

## 3. Login

- No Android, a app volta pelo deep link. Na Web, volta à origem de onde saiu (`Uri.base.origin`): `http://localhost:7357/` em desenvolvimento, ou o endereço do Pages.
- O cliente Google não muda: o Google só fala com `https://<ref>.supabase.co/auth/v1/callback`.
- Em desenvolvimento, `http://localhost:7357` tem de ser a Site URL do Supabase ou estar nas Redirect URLs.

## 4. Validar depois da primeira publicação

1. Abrir o endereço e entrar com Google. Tem de voltar à app com sessão iniciada.
2. Criar uma peça com foto e ver se aparece noutro dispositivo (guia 08 §7).
3. Instalar no iPhone pelo [guia 05 §5](05-instalar-android-e-pwa.md#5-adicionar-a-pwa-ao-iphone) e repetir pelo ícone.

Ainda por demonstrar (P-05): a reabertura sem rede no iPhone. A build usa o service worker por omissão do Flutter, ainda sem uma estratégia offline própria.

## Recuperação

| Sintoma | Ação |
|---|---|
| Aviso "Secrets CLOUDFLARE_… em falta" | Criar os dois secrets (§1) e voltar a correr |
| Cloudflare respondeu 403/401 | O token não tem Cloudflare Pages › Edit, ou é de outra conta |
| Login volta para localhost ou dá "redirect" inválido | Ver se o endereço está nas Redirect URLs (o resumo do job diz se o acrescentou) |
| Página vazia | Consola do browser; confirmar que `sqlite3.wasm` e `powersync_db.worker.js` existem no deploy |
| Versão antiga continua aberta | Fechar e reabrir a app; o index não fica em cache, mas o service worker pode precisar de uma segunda abertura |
| Ficheiro excede 25 MiB | O Pages Free não aceita; rever o artefacto (a build atual tem ~60 MB, nenhum ficheiro acima de 12 MB) |

Não limpar o armazenamento do browser nem reinstalar a PWA como reparação genérica: pode haver alterações por sincronizar.

Fontes: Cloudflare Pages Direct Upload e Wrangler, Flutter Web em [Fontes](../fontes.md). Próximo: [instalação](05-instalar-android-e-pwa.md).
