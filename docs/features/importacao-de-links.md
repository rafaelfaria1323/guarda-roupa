# Feature — Importação assistida de produtos por link

Estado: importante, mas posterior à fundação/MVP; suporte definido por loja e POC, não universal.

## Implementado (2026-11-04, qualquer site; aprende sozinho por domínio)

Decisão do utilizador (2026-11-04): aceitar **qualquer link** de loja, não só uma lista, e o importador deve ir-se adaptando sozinho aos sites que se usam. Substitui a lista fechada de P-12 (Zara, Uniqlo, Pull&Bear, Bershka), que fica só para dar o nome bonito a esses domínios. A função corre em **Supabase Edge Functions** (`supabase/functions/import-product`, Deno).

“Aprender sozinho” é feito com dados, não com código gerado: o parser é genérico e cada domínio ganha um perfil na base que se atualiza a cada importação. Um parser que se reescrevesse sozinho não seria seguro nem testável.

- **Qualquer site público.** Proteções de rede para a função não servir de proxy para redes internas:
  - só `https`, sem credenciais nem porta;
  - recusa IPs escritos à mão (em qualquer forma: `127.0.0.1`, `2130706433`, `0x7f.1`, IPv6) e nomes locais (`localhost`, `.local`, `.internal`, `.lan`, `.home.arpa`, ...);
  - quando o runtime deixa resolver DNS, recusa nomes que apontam para redes privadas, de loopback, link-local (incluindo `169.254.169.254`) ou de CGNAT. Sem DNS no runtime ficam as regras dos nomes. Limite conhecido: o `fetch` resolve o nome de novo, por isso um DNS que mude entre as duas resoluções não é apanhado;
  - redirecionamentos seguidos à mão (no máximo 3), cada um validado de novo; podem ir para outro site público;
  - 8 s de tempo, 2 MB por página e 5 MB por imagem; a página tem de ser HTML e a imagem JPEG, PNG ou WebP;
  - sem cookies nem login: um bloqueio é dito como `blocked`, nunca contornado.
- **Pedido autenticado**: a base valida o token, a allowlist (P-16) e a quota em `claim_import_quota()` (30 por hora, 200 por dia, imagens incluídas). Um link inválido ou interno é recusado antes de gastar quota.
- **Extração**, por ordem de confiança:
  1. JSON-LD `ProductGroup`/`Product` (também dentro de `@graph`);
  2. microdata schema.org `Product` (`itemprop`);
  3. Open Graph e Twitter cards;
  4. HTML simples: título, `meta description`, `link rel=image_src`. Só conta como produto com uma imagem; um título sozinho dá `no_metadata`.
  - Campos: nome, marca, descrição, cor, material, imagens absolutas `https` e variantes (cor, tamanho, SKU, imagem).
  - Cada campo diz a origem (`json-ld`, `microdata`, `open-graph`, `html`). A resposta lista o que é preciso confirmar: categoria, cores e posse sempre; a variante quando há várias; o material quando falta; o nome quando veio do título da página.
  - Só texto: as etiquetas são retiradas, as entidades descodificadas (também as vogais acentuadas) e os comprimentos limitados. Preço e stock ignoram-se.
- **Perfil por domínio** (`import_domains`, `record_import`): cada importação, boa ou má, conta para o domínio, com a origem dos dados. O estado sai das contagens:
  - `new` (ainda sem sucessos): “site novo”;
  - `testing` (já funcionou): “já funcionou”;
  - `works` (3 ou mais sucessos e o último correu bem): “costuma funcionar”;
  - `failing` (3 falhas seguidas): “costuma falhar”.
  O perfil não guarda links, produtos nem utilizadores. Se a base não responder, a importação segue como “site novo”.
- **Imagens**: `{image}` só copia uma imagem que a função ofereceu a esse utilizador numa pré-visualização há menos de um dia (`import_image_grants`, guardada como hash). Qualquer outra dá `image_not_offered`. Assim aceitar qualquer site não abre um proxy de imagens. Limite conhecido: `record_import` corre como o utilizador, por isso uma conta da allowlist que chamasse a RPC à mão conseguiria autorizar imagens a si própria. Mesmo assim continuam as regras de rede e a quota, e a allowlist é só o proprietário (P-16).
- **Respostas**: `ok`, `invalid_url`, `not_public`, `fetch_failed` (com `timeout`, `blocked`, `not_found`, `too_large`, `redirect_not_allowed`, …), `no_metadata`, `rate_limited` e `image_not_offered`. Uma página sem dados nunca dá um produto inventado.
- **Na app** (`lib/features/import/`): “Importar de um link” no formulário de peça nova, só com Supabase configurado.
  - Lê a página com a sessão do utilizador (`SupabaseProductImporter`, via `http`: as imagens vêm em binário). Sem sessão não faz pedidos.
  - A pré-visualização mostra:
    - o site e o estado (“site novo”, “já funcionou”, “costuma funcionar”, “costuma falhar”);
    - cada campo com a origem (“dados da página”, “pré-visualização da página: confirma”, “título da página: confirma”);
    - a descrição;
    - a escolha da variante (“Qual é a tua?”);
    - as imagens a copiar. Por omissão copia-se uma, porque cada cópia conta para a quota; a imagem da variante escolhida passa a ser a escolhida.
  - “Usar na peça nova” preenche o nome, a marca (ou o site), o material e as notas: descrição, cor na loja, tamanho e o link, que nunca é cortado.
  - As imagens juntam-se às fotos por guardar, processadas como as da galeria.
  - **A categoria e as cores escolhem-se sempre no formulário**; nada é gravado antes de “Guardar”.
  - Erros com mensagem própria: link inválido, endereço interno, página bloqueada, página inexistente, página sem dados, quota esgotada, conta sem acesso e função indisponível. Em todos há “Preencher à mão”, que segue só com o link nas notas.
- **Testes**:
  - Deno com fixtures **sintéticas** no CI: parser (JSON-LD, microdata, Twitter/HTML, título sozinho), regras de rede (IPs, nomes locais, DNS privado), redirecionamentos, limites, erros, imagens autorizadas e perfil;
  - SQL da quota e dos perfis;
  - Flutter com um importador falso e do cliente com `MockClient`.
- **Publicação** pelo workflow Supabase, com o secret `SUPABASE_ACCESS_TOKEN` (permissão `edge_functions_write`). Publicada desde 2026-11-04. Se a função não estiver publicada, a app mostra “A importação não está disponível agora”.
- **Por fazer**: o smoke com links reais ([tool/import/README.md](../../tool/import/README.md)). O ambiente de desenvolvimento na cloud não chega aos sites das lojas, por isso corre no Mac. Sites que bloqueiam pedidos automáticos (anti-bot) vão continuar a falhar: o perfil mostra-o como “costuma falhar” e fica a introdução manual.
- **Próximo passo possível**: usar as correções do utilizador (categoria escolhida, nome editado) para sugerir a categoria da próxima peça do mesmo site. Fica para depois: precisa de mais dados reais.

### Estado por loja (uso real)

| Loja | Resultado | Data | Notas |
|---|---|---|---|
| Uniqlo | Importa | 2026-11-05 | Testado pelo utilizador na PWA (iPhone) |
| Zara | Falha | 2026-11-05 | Inditex; por investigar (provável bloqueio a pedidos automáticos ou dados só via JavaScript/API interna) |
| Massimo Dutti | Falha | 2026-11-05 | Inditex, mesma plataforma da Zara; a correção deve servir às duas |

## Objetivo

Colar o link de um produto de qualquer loja, obter dados úteis e confirmar a peça realmente possuída. Cada site vai sendo conhecido pelo uso (perfil por domínio); nenhum é prometido como suportado.

## Estratégia recomendada

Função pequena em TypeScript, autenticada e limitada, que consulta páginas públicas autorizadas e extrai:

1. Product JSON-LD quando disponível.
2. Metadados Open Graph como alternativa parcial.
3. Nome, marca, descrição, imagens e variantes identificáveis.
4. Origem/confiança dos dados e campos que necessitam de confirmação.

Preço e stock não são necessários à recomendação de outfits. Um produto ter várias cores não identifica a variante que o utilizador tem.

## Fluxo

1. Colar URL e validar domínio/protocolo.
2. Consultar apenas fonte suportada.
3. Mostrar preview e escolher variante/imagem.
4. Confirmar categoria, cores, material conhecido e posse.
5. Persistir ficheiros permitidos, em vez de depender só de um link externo temporário.
6. Criar uma peça física com novo ID.

Sem metadados suficientes, abrir formulário manual com o link de origem. Informar “não suportado” ou erro real, não fingir uma importação concluída.

## Tecnologia e alojamento

Proposta original: Cloudflare Pages Functions com `HTMLRewriter`, perto do alojamento Web.

Como o backend passou a ser obrigatório, comparar Supabase Edge Functions para evitar um segundo serviço de execução. A escolha depende de quotas, validação de rede, bibliotecas e manutenção.

| Opção | Avaliação |
|---|---|
| Metadata/JSON-LD numa função | Recomendado: leve e sem browser remoto |
| Supabase Edge Functions | Alternativa forte por já existir Supabase; quotas a confirmar antes de escolher |
| Fetch direto no browser | CORS e proteção dos sites impedem suporte fiável |
| Scraping headless | Mais pesado, frágil e difícil de manter no orçamento gratuito |
| LLM para ler cada página | Não resolve acesso, variantes ou direitos; custo desnecessário |
| Introdução manual | Alternativa obrigatória e utilizável |

## Limites de execução e acesso

Qualquer site público (decisão de 2026-11-04, antes era uma whitelist); autenticação, allowlist, rate limit, timeout, limite de bytes e redirects. Validar destino em cada redirect e impedir acesso a redes internas/metadata. Não oferecer um proxy público de URLs arbitrários: só utilizadores autorizados, com quota, e imagens só as oferecidas numa pré-visualização.

Não contornar login, anti-bot, paywalls ou termos. Não executar HTML/scripts importados na app; descrições são dados tratados.

Workers Free tem CPU limitada; não prometer um browser automatizado gratuito por trás da feature.

## Qualidade e manutenção

Guardar amostras de resposta autorizadas para regressão de parsing e fazer smoke separado com link real. Testes com fixtures não demonstram que a loja continua acessível.

O estado de cada domínio vem do uso real (perfil em `import_domains`), não de uma promessa: “costuma funcionar” só depois de três sucessos e com o último bem-sucedido.

## Ações e aceitação

O utilizador fornece links de exemplo e confirma a variante. Não precisa de enviar credenciais de lojas.

E2E-12 do [plano](../plano-e2e.md): link de uma loja, variante, página sem metadata, erro/timeout, endereço interno recusado e criação final persistente sem peça inventada.

Fonte/termos: [registo](../fontes.md). Pendência P-12.
