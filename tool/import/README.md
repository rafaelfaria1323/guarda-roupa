# Smoke da importação por link (P-12)

A função `import-product` só aceita Zara, Uniqlo, Pull&Bear e Bershka, e
todas estão **em teste** (`poc`). Uma loja passa a suportada quando este
smoke funciona com links reais. Os testes com fixtures não provam isso.

## Correr no Mac (sem conta nem quota)

1. Instalar o Deno: `brew install deno`.
2. Na raiz do repositório:

   ```bash
   deno run --allow-net supabase/functions/import-product/cli.ts "https://www.zara.com/pt/pt/…-p0000000.html"
   ```

3. Ver o resultado:
   - `ok`: mostra o que a app pré-preencheria (nome, marca, descrição,
     material, imagens, variantes) e de onde veio cada campo (`json-ld`
     ou `open-graph`).
   - `copyableImages`: quantas imagens estão num domínio de imagens da
     loja que a função pode copiar. Se for 0 com imagens na lista, o
     domínio de imagens da loja (`stores.ts`) está errado ou mudou.
   - `fetch_failed` / `blocked`: a loja recusou o pedido (ex.: anti-bot).
     Não se contorna: fica a introdução manual com o link.
   - `no_metadata`: a página não traz JSON-LD nem Open Graph no HTML.

Repetir com 2–3 produtos por loja, de preferência um com várias cores.
Registar em `docs/features/importacao-de-links.md` (tabela "Lojas") a data,
o resultado e o que falhou. Só depois mudar `status` para `supported`.

## Com a função publicada

A função corre como o utilizador com sessão (allowlist P-16) e tem quota:
30 pedidos por hora, 200 por dia (`claim_import_quota`). Para a publicar
pelo CI é preciso o secret `SUPABASE_ACCESS_TOKEN` (ver
`.github/workflows/supabase.yml`).
