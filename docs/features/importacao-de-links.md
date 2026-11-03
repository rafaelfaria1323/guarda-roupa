# Feature — Importação assistida de produtos por link

Estado: importante, mas posterior à fundação/MVP; suporte definido por loja e POC, não universal.

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
