# Feature — Conjuntos guardados e ocasiões

Estado: necessária no MVP.

## Implementado (incremento 4)

- Separador **Conjuntos**: lista (nome ou as primeiras peças, nº de peças, ocasiões, “Incompleto” e aviso de peças indisponíveis) e editor com nome opcional (até 120 caracteres), ocasiões (casual, trabalho (smart casual), noite/saída), peças e papel de cada uma.
- O papel é sugerido pela categoria e pode ser corrigido. `main_top`, `bottom`, `one_piece` e `footwear` são únicos; `mid_layer`, `outer_layer` e `accessory` repetem-se. 1–20 peças, sem repetir a mesma.
- “Falta: …” (calçado e top+parte de baixo, ou peça única) é só um aviso: um conjunto incompleto guarda-se na mesma. Casaco e acessórios nunca são obrigatórios.
- Peças a lavar/a secar/indisponíveis, arquivadas ou eliminadas mantêm-se no conjunto com aviso; nada muda sozinho. Peças novas têm de estar ativas.
- **Vesti hoje → Usar um conjunto** preenche a escolha com as peças disponíveis do conjunto (avisa as que ficaram de fora). A utilização fica registada à parte: editar ou eliminar o conjunto depois não a altera.
- Dados: tabela `outfits` com `items` em JSON (`[{garment_id, role}]`), escrita por `apply_outfit_operation` (`create_outfit`, `edit_outfit` campo a campo, `delete_outfit`), sincronizada pelo stream `user_outfits`.
- Backup (formato v3): os conjuntos entram e são recuperados com as peças novas.
- **Da sugestão para o conjunto (2026-11-06):** “Guardar como conjunto” em “Sugestões para hoje” guarda as peças e papéis da sugestão (sem a camada opcional), com a ocasião escolhida.
- **No motor:** os conjuntos guardados são propostos quando as peças servem e passam à frente de outros iguais em avisos, no dia e na semana ([motor](motor-de-combinacoes.md)).
- **Peça em falta (2026-11-06):** se só uma peça do conjunto não serve hoje, a sugestão traz o conjunto com outra no lugar dela e diz qual trocou; o conjunto guardado não muda. “Guardar como conjunto” continua disponível para guardar a variante como outro conjunto.

## Objetivo

Guardar composições reutilizáveis, atribuir uma ou mais ocasiões e recuperar sugestões adequadas sem confundir composição, plano e utilização.

Ocasiões iniciais confirmadas: casual, trabalho (smart casual), jantares/saídas. O id técnico continua `work_casual`; o nome mostrado passou de “Trabalho informal” para “Trabalho (smart casual)” (P-19: o trabalho não pede roupa formal). Formalidade por ocasião (decidido 2026-11-06): uma peça sem ocasiões marcadas serve para a noite se for casual cuidado ou arranjada, e para o dia a dia e o trabalho com qualquer formalidade (no trabalho vai-se muitas vezes descontraído); marcar ocasiões na peça prevalece sobre esta regra ([motor](motor-de-combinacoes.md)). Etiquetas futuras podem ser adicionadas sem misturar nomes traduzidos com IDs técnicos.

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
