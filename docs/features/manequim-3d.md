# Feature — Manequim 3D dos conjuntos (para mais tarde)

Estado: **ideia registada, adiada** (decisão do utilizador, 2026-11-04). Não faz parte do MVP nem dos incrementos 7–9; volta-se a ela depois. Pendência P-20.

## Objetivo

Ver um conjunto vestido num manequim 3D, com zoom e a rodar à volta, a partir das peças do guarda-roupa.

## O problema de fundo

As peças existem como fotografias 2D. Vesti-las num manequim exige um modelo 3D de cada peça que assente no corpo. Gerar isso a partir das fotos com qualidade ainda não é viável dentro do orçamento (sem custos, offline, PWA e Android).

## Opções avaliadas

| Opção | Avaliação |
|---|---|
| Manequim com **moldes 3D por categoria** (t-shirt, camisa, camisola, calças, saia, casaco, sapatilhas, botas, ...) pintados com as cores da peça; camadas pelos papéis do motor (base, meio, casaco) | **Recomendado para começar.** Offline, sem custos, funciona na PWA do iPhone e no Android. Representativo, não fiel: “uma camisa azul”, não a tua camisa. O maior trabalho são os modelos (manequim + 15–20 moldes, feitos em Blender ou CC0) |
| O mesmo com a **fotografia como textura** do molde | Mais parecido, mas só a frente fica bem (lados e costas esticados). Precisa de recortar o fundo da foto, o que liga à [IA local](ia-local.md) (P-14). Experiência depois da primeira |
| **3D gerado a partir das fotos** ou **provador virtual com IA** | Precisa de servidor com GPU e custa por pedido; lento e com qualidade irregular para roupa. Contra a regra de não ter uma API paga escondida. Só numa fase comercial, se fizer sentido |

## Primeira POC proposta (quando se retomar)

No ecrã do conjunto: um manequim neutro, moldes só para as categorias mais usadas (t-shirt, camisa, camisola, calças, casaco, sapatilhas), cores tiradas das peças, rodar e fazer zoom. Serve para decidir se vale a pena investir nos modelos todos.

Por decidir ao retomar: modelos simples gerados por código (substituíveis) ou modelos feitos/obtidos com licença livre; visualizador (por exemplo `model-viewer` na Web e uma `WebView` no Android, ou um renderizador nativo); limites de desempenho no iPhone.
