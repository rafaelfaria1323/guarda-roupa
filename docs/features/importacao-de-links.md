# Feature — Importação assistida de produtos por link

Estado: importante, mas posterior à fundação/MVP; suporte definido por loja e POC, não universal.

## Implementado (2026-11-04, função e app; lojas em teste)

- Decisão (P-12): Zara, Uniqlo, Pull&Bear e Bershka primeiro; a função corre em **Supabase Edge Functions** (`supabase/functions/import-product`, Deno).
- Lista fechada de lojas (`stores.ts`), todas `poc`: nenhuma é anunciada como suportada sem o [smoke](../../tool/import/README.md) com links reais.
- Proteções de rede:
  - só `https`, sem credenciais nem porta, e só domínios exatos da lista (não aceita IPs nem redes internas);
  - redirecionamentos seguidos à mão (no máximo 3), cada um validado de novo e sempre dentro da mesma loja;
  - 8 s de tempo, 2 MB por página e 5 MB por imagem; a página tem de ser HTML e a imagem JPEG, PNG ou WebP;
  - sem cookies nem login: um bloqueio é dito como `blocked`, nunca contornado.
- Pedido autenticado: a base valida o token, a allowlist (P-16) e a quota em `claim_import_quota()` (30 por hora, 200 por dia). Um link de outra loja é recusado antes de gastar quota.
- Extração: JSON-LD `ProductGroup`/`Product` (também dentro de `@graph`), com Open Graph como alternativa parcial. Campos extraídos: nome, marca, descrição, cor, material, imagens absolutas `https` e variantes (cor, tamanho, SKU, imagem).
  - Cada campo diz a origem (`json-ld` ou `open-graph`) e a resposta lista o que é preciso confirmar: categoria, cores e posse sempre; a variante quando há várias; o material quando falta.
  - Só texto: as etiquetas são retiradas, as entidades descodificadas e os comprimentos limitados. Preço e stock ignoram-se.
- Respostas: `ok`, `unsupported_store`, `invalid_url`, `fetch_failed` (com `timeout`, `blocked`, `not_found`, `too_large`, …), `no_metadata` e `rate_limited`. Uma página sem dados nunca dá um produto inventado.
- Imagens: `{image}` copia uma imagem só de um domínio de imagens da própria loja, para a peça ficar com o ficheiro e não com um link temporário.
- Testes Deno com fixtures **sintéticas** no CI (parser, regras de URL, redirecionamentos, limites, erros e quota) e testes SQL da quota. Publicação pelo workflow Supabase com o secret `SUPABASE_ACCESS_TOKEN`.
- Na app (`lib/features/import/`): “Importar de um link” no formulário de peça nova, só com Supabase configurado.
  - Lê a página com a sessão do utilizador (`SupabaseProductImporter`, via `http`: as imagens vêm em binário). Sem sessão não faz pedidos.
  - A pré-visualização mostra a loja “em teste”, cada campo com a origem (“dados da página” ou “pré-visualização da página: confirma”), a descrição, a escolha da variante (“Qual é a tua?”) e as imagens a copiar. Por omissão copia-se uma imagem, porque cada cópia conta para a quota; a imagem da variante escolhida passa a ser a escolhida.
  - “Usar na peça nova” preenche nome, marca (ou a loja), material e notas (descrição, cor na loja, tamanho e o link; o link nunca é cortado) e junta as imagens às fotos por guardar, processadas como as da galeria. **A categoria e as cores escolhem-se sempre no formulário**; nada é gravado antes de “Guardar”.
  - Erros com mensagem própria: loja fora da lista, link inválido, página bloqueada, página inexistente, página sem dados, quota esgotada, conta sem acesso e função indisponível. Em todos há “Preencher à mão”, que segue só com o link nas notas.
  - Testes com um importador falso (fluxo completo, erros, botão ausente sem Supabase) e do cliente com `MockClient`.
- Por fazer: o smoke com links reais e confirmar os domínios das imagens. O ambiente de desenvolvimento na cloud não chega aos domínios das lojas, por isso o smoke corre no Mac. A função só fica publicada quando o secret `SUPABASE_ACCESS_TOKEN` existir; até lá a app mostra “A importação não está disponível agora”.

### Lojas

| Loja | Estado | Smoke com links reais |
|---|---|---|
| Zara | Em teste | Por fazer |
| Uniqlo | Em teste | Por fazer |
| Pull&Bear | Em teste | Por fazer |
| Bershka | Em teste | Por fazer |

## Objetivo

Colar um link, por exemplo de Zara ou Uniqlo, obter dados úteis e confirmar a peça realmente possuída. As restantes lojas precisam de identificação e validação individual.

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

Whitelist de lojas suportadas; autenticação, rate limit, timeout, limite de bytes e redirects. Validar destino em cada redirect e impedir acesso a redes internas/metadata. Não oferecer um proxy público de URLs arbitrários.

Não contornar login, anti-bot, paywalls ou termos. Não executar HTML/scripts importados na app; descrições são dados tratados.

Workers Free tem CPU limitada; não prometer um browser automatizado gratuito por trás da feature.

## Qualidade e manutenção

Guardar amostras de resposta autorizadas para regressão de parsing e fazer smoke separado com link real. Testes com fixtures não demonstram que a loja continua acessível.

Um domínio só passa a “suportado” com evidência, política de manutenção e comportamento conhecido para variantes/erros.

## Ações e aceitação

O utilizador fornece links de exemplo e confirma a variante. Não precisa de enviar credenciais de lojas.

E2E-12 do [plano](../plano-e2e.md): link suportado, variante, página sem metadata, erro/timeout, domínio não autorizado e criação final persistente sem peça inventada.

Fonte/termos: [registo](../fontes.md). Pendência P-12.
