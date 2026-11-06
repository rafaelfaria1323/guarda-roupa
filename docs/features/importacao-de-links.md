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
- **Pedidos**: `{url}` (a função lê a página), `{url, page}` (página partilhada pelo [atalho do iPhone](#atalho-do-iphone)) e `{image}`.
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
- **Smoke com links reais (2026-11-06, na cloud, `cli.ts`)**, sem contornar bloqueios:

  | Loja | Resultado |
  |---|---|
  | Uniqlo (2 produtos) | `ok`, só Open Graph: nome e uma imagem; sem material, cor nem variantes (a página monta o resto com JavaScript) |
  | H&M (2), Mango, Levi’s, Decathlon (2) | `blocked` (403): a loja recusa pedidos automáticos; fica a introdução manual ou o atalho do iPhone |
  | Salsa | `not_found` (404): o produto já não existia |

  Daqui saiu uma correção: o nome tirado do título da página já não traz a loja no fim (“T-shirt | UNIQLO PT” → “T-shirt”), por `og:site_name` ou pelo domínio. Falta experimentar as lojas que o utilizador usa, no telemóvel ([tool/import/README.md](../../tool/import/README.md)). Nas lojas que bloqueiam, o caminho é o atalho do iPhone, que manda a página já aberta no Safari.
- **Próximo passo possível**: usar as correções do utilizador (categoria escolhida, nome editado) para sugerir a categoria da próxima peça do mesmo site. Fica para depois: precisa de mais dados reais.

### Atalho do iPhone

Para as lojas que bloqueiam (Zara, Massimo Dutti), há um atalho do iPhone, "Importar para o fio" ([guia](../guias/09-atalho-importar-iphone.md)), criado com o utilizador a 2026-11-05. O script de teste leu os dados da Zara; o fluxo completo na app falta confirmar no iPhone.

- **Como funciona:** o utilizador abre a peça no Safari e partilha-a com o atalho. O atalho corre um script na página já aberta, que produz um JSON com `fio: 1`, o link, o título, os blocos JSON-LD e as meta tags `og:`/`twitter:`/`product:`. Há dois modos:
  - **Envia logo para o fio (por omissão):** o atalho faz POST do JSON à função com a chave pessoal no cabeçalho `x-fio-key` e mostra a resposta numa notificação. A peça fica na caixa **Enviadas pelo atalho** (ver abaixo).
  - **Copiar e colar:** o atalho copia o JSON e, no fio, "Colar do atalho" (ou colar no campo do link) envia `{url, page}` à função com a sessão.
- **Não se contorna nada:** a página foi aberta pelo browser do utilizador e a função não pede nada à loja. Confirmado com a Zara: o Safari mostra o `ProductGroup` completo em JSON-LD e o Open Graph.
- **Na função** (`shared_page.ts`):
  - o `page` é validado: até 10 blocos JSON-LD e 200 kB, até 80 meta tags e o título limitado;
  - é remontado como HTML mínimo e passa pelo parser de sempre;
  - o link continua a passar pelas regras de rede e a importação gasta quota como as outras.
- **Imagens:** `record_import` com o resultado `shared` autoriza as imagens oferecidas (que se copiam depois como sempre; as da Zara, em `static.zara.net`, copiam-se sem bloqueio). **Não mexe nas contagens do domínio**, porque o perfil diz se o *link* funciona sozinho. A etiqueta da pré-visualização diz "Zara · pelo atalho".
- **Limite conhecido:** como os dados vêm do cliente, uma conta da allowlist podia oferecer a si própria imagens de qualquer site público. É o mesmo limite de `record_import` descrito acima: as regras de rede, a quota e a allowlist (só o proprietário) mantêm-se.
- **Só iPhone:** no Android ficaria para um browser dentro da app, que não está feito.

#### Caixa "Enviadas pelo atalho"

O atalho não tem sessão, por isso autentica-se com uma **chave pessoal** criada na app (Importar de um link → Atalho do iPhone). A chave (`fio_` + 244 bits aleatórios) só se mostra quando é criada; a base guarda o SHA-256. "Nova chave" substitui a anterior e "Desligar" apaga-a.

- **Pedido:** `POST /functions/v1/import-product?apikey=<chave publicável>` com `x-fio-key` e o JSON do script. A `apikey` vai no link porque é configuração pública e o atalho não tem outra forma de a ter.
- **Na função:** valida o JSON (as mesmas regras do `page`), passa o link pelas regras de rede, lê o produto do HTML remontado e entrega a pré-visualização a `submit_import_inbox()` como anónimo. Responde em **texto simples em português**, para a notificação do atalho: "Enviada para o fio: …", chave inválida (401), sem acesso (403), quota (429), caixa cheia (409), página sem produto (422).
- **Na base** (`submit_import_inbox`): a chave identifica o dono; vale a allowlist dele e **a mesma quota** das importações com sessão (30/hora, 200/dia). No máximo 20 peças à espera; cada uma expira ao fim de 7 dias. As imagens oferecidas ficam autorizadas enquanto a peça espera.
- **Na app — entram sozinhas no Armário (decisão do utilizador a 2026-11-06):** quando o Armário abre ou a app volta ao primeiro plano, cada peça da caixa passa a cartão, como se tivesse sido introduzida à mão (`shortcut_inbox.dart`). O que não vier da loja fica por omissão e muda-se depois no cartão:
  - **categoria** pelo nome do produto, depois pela categoria da loja (JSON-LD `category`, `product:category` ou o *breadcrumb* `BreadcrumbList`, que a função devolve em `category`) e por fim pelo caminho do link (`category_from_text.dart`, palavras em português, inglês e espanhol; senão "Outro"). Ganha a primeira palavra forte do texto; palavras de tecido ou estilo ("ganga", "malha", "polo", "sweat") só contam se não houver outra, para "Camisa de ganga" ser camisa;
  - **cores:** se a loja só der uma cor e o nome for conhecido ("Azul-marinho", "Navy", "Crudo"…), usa-se esse nome (até 3 cores, por exemplo "Azul / branco"); senão vêm da foto de capa, que tira o fundo de estúdio mesmo em gradiente ([fotografias](fotografias-e-ficheiros.md)). Sempre por confirmar (`confirmed: false`);
  - **foto:** só a primeira imagem, porque cada cópia gasta quota;
  - nome, marca e material da loja; nas **notas**, a descrição, a cor da loja quando só há uma e o link (o tamanho fica para o utilizador).
  Cada peça sai da caixa depois de criada; se falhar, fica para a próxima vez. Um aviso diz quantas entraram. Para as importações por link, com a pré-visualização, mantém-se a regra de confirmar no formulário.
- **Ainda à mão, se preciso:** as peças que estejam na caixa também aparecem no topo de Importar de um link (usar ou descartar).
- **Pins e Instagram (2026-11-06):** a mesma caixa recebe inspirações. Uma página do Pinterest ou do Instagram partilhada pelo atalho vai para o Perfil (inspirações), não para o Armário ([inspirações](inspiracoes-e-estilo.md#pinterest)). Um link destes sites colado em Importar de um link não é lido, porque o robots.txt do Pinterest recusa leitores automáticos: a app diz para o partilhar pelo atalho.
- **Riscos:** quem tiver a chave só consegue pôr peças na caixa do dono, dentro da quota e do limite de 20; não lê nada. Uma chave perdida desliga-se na app.

### Estado por loja (uso real)

| Loja | Resultado | Data | Notas |
|---|---|---|---|
| Uniqlo | Importa | 2026-11-05 | Testado pelo utilizador na PWA (iPhone) |
| Zara | Bloqueada | 2026-11-05 | Akamai Bot Manager: responde 200 com um desafio JavaScript (`bm-verify`) em vez do produto, a qualquer pedido sem browser. Não se contorna; a app diz "Esta loja bloqueia leituras automáticas" e segue para "Preencher à mão". **No iPhone importa pelo [atalho](#atalho-do-iphone)** |
| Massimo Dutti | Bloqueada | 2026-11-05 | O mesmo desafio Akamai da Zara (Inditex). Pull&Bear e Bershka, também Inditex, devem ter o mesmo comportamento. No iPhone, pelo atalho |

**Desafios anti-bot (2026-11-05).** Antes, uma página de desafio passava por "página sem dados" (`no_metadata`), o que enganava. Agora, se a página não tem produto e traz as marcas de um desafio conhecido (Akamai `bm-verify`, Cloudflare "Just a moment...", DataDome, PerimeterX), a resposta é `fetch_failed` com `blocked` (`challenge.ts`). Só se olha para isso quando não há produto, porque algumas páginas normais carregam os scripts destes serviços. Resolver o desafio (correr o JavaScript, imitar um browser) seria contornar o anti-bot, o que está fora das regras desta funcionalidade.

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
