# Feature — Conjuntos guardados e ocasiões

Estado: necessária no MVP.

## Objetivo

Guardar composições reutilizáveis, atribuir uma ou mais ocasiões e recuperar sugestões adequadas sem confundir composição, plano e utilização.

Ocasiões iniciais confirmadas: casual, trabalho informal, jantares/saídas. Etiquetas futuras podem ser adicionadas sem misturar nomes traduzidos com IDs técnicos.

## Estrutura e papéis

Cada composição referencia peças físicas e o papel que desempenham naquele conjunto:

- Top principal + parte inferior + calçado.
- Peça única + calçado.
- Camadas e acessórios adicionais quando fazem sentido.

Uma t-shirt pode ocupar `main_top` sem `outer_layer`. Também pode ser uma camada inferior noutro contexto. A mesma peça não ocupa dois lugares no mesmo conjunto.

O molde exato para cada estilo/ocasião é configurável; não tornar casacos ou acessórios universais obrigatórios.

## Fluxo

1. Escolher peças manualmente ou guardar uma proposta do motor.
2. Confirmar composição, nome opcional e ocasiões.
3. Reabrir para editar ou usar no planeamento.
4. Se uma peça estiver indisponível, mostrar aviso e propor substituição.
5. Quando planeado, criar composição independente da definição guardada.

Editar um conjunto guardado não altera fotografias históricas, composição realmente usada ou plano aceite sem uma ação explícita.

## Tecnologia

Entidades `Outfit`, `OutfitItem`, `OutfitOccasion` e repositório dedicado; Drift local e sync partilhada. Preview composto por imagens das peças; não há prova virtual.

## Alternativas

| Opção | Avaliação |
|---|---|
| Relações peça/papel/ocasião | Recomendado: composição verificável e pesquisa por disponibilidade |
| Guardar só uma colagem | Útil como preview, insuficiente para histórico e substituições |
| Duplicar as peças em cada conjunto | Rejeitado: perde identidade, disponibilidade e rotação comuns |
| Ocasião inferida só por IA | Adiada; preferências humanas continuam necessárias |

## Falhas e ações do utilizador

Uma peça arquivada mantém a referência histórica, mas não é candidata a nova sugestão. Não apagar conjuntos silenciosamente quando uma peça deixa de estar ativa.

O utilizador escolhe ocasiões e pode corrigir o papel sugerido. Não precisa de configurar serviços externos para usar esta feature depois da fundação.

## Aceitação

E2E-03 do [plano](../plano-e2e.md): criar conjunto com t-shirt, calças e ténis, sem casaco; classificar com várias ocasiões; editar o guardado sem alterar uma utilização antiga; sinalizar indisponibilidade sem alterar automaticamente planos.

Referências: [modelo](../modelo-de-dados.md), [motor](motor-de-combinacoes.md).
