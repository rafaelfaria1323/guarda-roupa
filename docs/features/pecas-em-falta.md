# Feature — Peças que faziam falta

Estado: implementado a 2026-11-06, a pedido do utilizador ("tens sapatos brancos, falta uns pretos"; "uma sweat cinzenta, falta uma navy"). Fica no **Resumo do armário**. Falta experimentar com o armário e as inspirações reais.

## Decisão

- São **só ideias**: nada se compra nem se adiciona sozinho. "Já tenho" abre a criação de peça; "Não me interessa" esconde a ideia neste aparelho.
- As faltas calculam-se **no aparelho**, sem rede e sem custo. O Gemini é opcional e só acrescenta ideias concretas com marcas.
- Marcas: ao nível das que já tens, mais baratas e mais caras (decisão do utilizador: "ambas"). Com orçamento por peça opcional (decisão do utilizador).
- **Nunca modelos nem preços** vindos do Gemini, porque podia inventá-los. Cada marca abre uma pesquisa (Google) com a descrição, onde se confirma o preço e se existe. Para trazer uma peça encontrada, cola-se o link no [importador](importacao-de-links.md).

## Faltas calculadas no aparelho

Contam só peças não arquivadas (as que estão a lavar continuam a contar). Por ordem, até 6:

| Falta | Quando |
|---|---|
| Ainda não tens … | Nenhuma parte de cima, de baixo, calçado ou casaco (um vestido conta como parte de baixo se não houver partes de cima) |
| Uma peça em … | Cor que aparece na paleta das inspirações e em nenhuma peça (até 3, as que se repetem mais primeiro; cor mais próxima das de referência) |
| Algo mais arranjado em … | Há inspirações "arranjado" e nenhum calçado ou parte de baixo arranjada |
| Só tons claros / escuros em … | Calçado, partes de baixo ou casacos todos claros (Oklab L ≥ 0,75) ou todos escuros (≤ 0,45); sugere preto, ou branco/bege |
| Mais uma parte de baixo | Quatro ou mais partes de cima por cada parte de baixo |

Código: `lib/features/shopping/domain/wardrobe_gaps.dart`.

## Com o Gemini ligado

Botão **Sugerir peças e marcas** (e **Outras ideias**), com o campo **Até (por peça)** em euros.

1. A app manda só texto: as peças (categoria, nome, **marca**, formalidade, cores), as etiquetas das inspirações (título, paleta, formalidade, padrões, texturas, ocasiões, proporções; nunca imagens nem links), as faltas acima, o orçamento e as ideias postas de lado. Nunca notas, preços nem fotos.
2. A função `stylist` (`kind: "shopping"`, `supabase/functions/stylist/shopping.ts`) valida o pedido antes de gastar quota e pede 3 a 5 ideias: categoria, cor, descrição curta, porquê, texto de pesquisa e 3 a 4 marcas (`same`, `cheaper`, `pricier`).
3. Só passam ideias com categoria conhecida, texto e pelo menos uma marca válida.
4. Na Web, cada marca abre a pesquisa num separador novo; fora da Web, copia o texto da pesquisa.

Usa a mesma quota e a mesma opção do [Gemini](ia-gemini.md).

## Dados

Só no aparelho, em `local_settings`: `shopping_budget` (euros) e `shopping_dismissed` (lista JSON de chaves, ex.: `onlyLight:footwear:black`, `idea:sneakers:black`). Ver [modelo de dados](../modelo-de-dados.md#leitura-de-fotos-com-o-gemini-2026-11-06).
