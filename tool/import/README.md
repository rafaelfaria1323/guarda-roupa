# Smoke da importação por link (P-12)

A função `import-product` aceita o link de um produto de **qualquer site
público**. Cada site ganha um perfil na base que se atualiza sozinho a cada
importação (“site novo”, “já funcionou”, “costuma funcionar”, “costuma
falhar”). Os testes com fixtures sintéticas não provam que um site real
funciona: isso só se vê com este smoke ou com o uso.

## Correr no Mac (sem conta nem quota)

1. Instalar o Deno: `brew install deno`.
2. Na raiz do repositório:

   ```bash
   deno run --allow-net supabase/functions/import-product/cli.ts "https://loja.example/produto"
   ```

3. Ver o resultado:
   - `ok`: mostra o que a app pré-preencheria (nome, marca, descrição,
     material, imagens, variantes) e de onde veio cada campo (`json-ld`,
     `microdata`, `open-graph` ou `html`). `html` quer dizer que só havia o
     título da página: a app pede para confirmar o nome.
   - `fetch_failed` / `blocked`: o site recusou o pedido (ex.: anti-bot).
     Não se contorna: fica a introdução manual com o link.
   - `no_metadata`: a página não traz dados de produto nem imagem no HTML
     (por exemplo, páginas montadas só com JavaScript).
   - `not_public`: o link aponta para um endereço interno ou local.

Vale a pena experimentar 2–3 produtos de cada loja que se usa, de preferência
um com várias cores. Se uma loja importante der `no_metadata` ou dados
errados, guardar uma cópia da página em `fixtures/` (com o nome da loja e a
data) e abrir uma tarefa para afinar o parser.

## Com a função publicada

A função corre como o utilizador com sessão (allowlist P-16) e tem quota:
30 pedidos por hora, 200 por dia, imagens incluídas (`claim_import_quota`).
Só copia imagens que ofereceu a esse utilizador numa pré-visualização
recente. Para a publicar pelo CI é preciso o secret `SUPABASE_ACCESS_TOKEN`
(ver `.github/workflows/supabase.yml`).
