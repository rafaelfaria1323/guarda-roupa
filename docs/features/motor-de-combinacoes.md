# Feature — Motor explicável de combinações

Estado: recomendado para o MVP; regras finas, pesos e limites de pesquisa a calibrar.

## Implementado (2026-11-03): núcleo do motor diário

Dart puro em `lib/features/engine/domain/` (`DailyEngine.suggest`), sem UI nem previsão ainda.

- **Entradas:** `WardrobeSnapshot` (peças, utilizações, limpezas, valores de lavagem/rotatividade, preferências) e `SuggestionRequest` (dia, ocasião opcional, condições opcionais, limites de conforto, seed, número de resultados — 3 por omissão).
- **Modelos:** top principal + parte de baixo + calçado, ou peça única + calçado. A t-shirt chega como top único. **Camada por baixo (2026-11-06):** uma camisola, sweat ou casaco de malha leva por baixo uma peça leve (t-shirt, top, camisa ou polo, não quente), de preferência sem avisos: a de baixo fica como top principal e a malha como camada intermédia; o conforto (e o casaco) decide-o a malha. Sem peça leve disponível, a malha vai sozinha. Nas trocas, uma malha troca por outra malha e a peça de baixo por outra leve; na semana e no plano conta a de cima (cor do dia, repetidas, casaco em falta). Casaco só quando o conforto o pede (frio com top leve/médio) ou como camada opcional à parte (ameno, ou chuva/vento com um casaco adequado).
- **Obrigatório:** só peças não arquivadas e disponíveis; nenhuma peça em dois papéis; uma peça com ocasiões indicadas que não incluem a pedida fica de fora. Sem ocasiões indicadas conta a formalidade (decidido 2026-11-06): à noite servem casual cuidado e arranjado; no dia a dia e no trabalho qualquer uma (no trabalho vai-se muitas vezes descontraído, ex. t-shirt ou hoodie com jeans). Uma peça descontraída sem ocasiões fica de fora da noite, e as que servem levam a nota “para noite, pela formalidade”. Sem ocasiões nem formalidade é desconhecido: entra com nota. As ocasiões marcadas prevalecem sempre.
- **Ordem de cada papel, sem pesos:** conforto (serve › serve com casaco › desconhecido › não serve), chuva/vento (casaco e calçado), rotatividade (elegíveis primeiro, P-06), preferências (gosto − evito), menos usadas em 30 dias, usadas há mais tempo, seed. Uma peça confortável mas dentro do intervalo de rotatividade fica à frente de uma elegível que não serve.
- **Preferências:** cor (RGB de referência), padrão, textura e formalidade (2026-11-06), em cada peça, nas ocasiões da preferência (vazio = sempre). Combinações de cor contam no conjunto (ver abaixo).
- **Lavagem (P-07):** só aviso.
- **Conjuntos guardados (2026-11-06):** o motor propõe também os conjuntos guardados da ocasião pedida (sem ocasiões = sempre; sem ocasião pedida = todos), se as peças servirem hoje: disponíveis, não arquivadas e da ocasião. Se **só uma** não serve (a lavar, arquivada, apagada ou de outra ocasião), entra no lugar dela a melhor do mesmo papel que não é do conjunto, com a nota “Do teu conjunto Sexta, com Preta em vez de Azul”; com duas ou mais em falta já não é o mesmo conjunto e não entra. O casaco decide-o o tempo, como nos outros; a camada intermédia do conjunto entra se ainda servir (senão vai sem ela); acessórios ainda não entram. Um conjunto que contém todas as peças de um guardado (sem contar o casaco) leva a nota “Um dos teus conjuntos” e conta como **mais uma preferência**: passa à frente de outro igual em avisos, nunca de um com menos avisos (uma peça a lavar ou dentro da rotatividade continua a pesar). Vale também na semana e nas trocas.
- **Conjuntos:** o i-ésimo conjunto junta a i-ésima peça de cada papel; repetidos saem. Ordem: completos, menos avisos, mais preferências (das peças e da combinação de cor), formalidade coerente, menos padrões/texturas a competir, peças mais bem ordenadas, seed (FNV-1a, igual em todas as plataformas).
- **Resultado:** peças/papéis com notas (ocasião, conforto, chuva/vento, rotatividade, uso recente, preferências, lavagem), camada opcional, papéis em falta e estado: válido, parcial (falta calçado ou casaco), nada encontrado (há peças mas nenhuma serve, com o motivo por papel: indisponível ou outra ocasião) e dados insuficientes (não há peças para nenhum modelo). Sem condições, diz que não aplicou regras de conforto.

### "Sugestões para hoje" (2026-11-03)

Cartão em Hoje (antes Planeador), por baixo de "Vesti hoje":

- **Tempo:** a previsão de hoje no local escolhido (sensação média, mínimo e máximo das 8 h às 20 h, chuva, vento) com a hora a que foi obtida, se é antiga e a atribuição; botão para atualizar.
  - Sem previsão, diz porquê e sugere sem regras de conforto.
  - Em alternativa, tempo indicado à mão (Calor, Ameno, Frio e chuva), sempre identificado como manual, até voltar à previsão. Usa 26, 18 ou 8 °C de sensação.
- **Ocasião:** qualquer, ou uma das três.
- **Conjuntos:** até 3 sugestões, cada uma com peças, papel e notas por peça (avisos a laranja escuro), o que falta, a camada opcional e as lacunas por papel. Em Hoje aparece uma de cada vez, em flat-lay: "Mostrar outro" passa à seguinte e, depois da última, muda a seed. As razões ficam atrás de "Porquê este"; os avisos ficam à vista.
- **Sem conjunto possível:** explica os dados insuficientes ou porque nada serve.
- **"Vou vestir isto":** abre "Vesti hoje" com as peças já escolhidas. Só conta como uso depois de guardar (P-08). As escolhas do cartão não ficam guardadas.

### Conjunto: cores, padrões e texturas (2026-11-04)

`OutfitHarmony` (`lib/features/engine/domain/outfit_harmony.dart`) lê o conjunto sem a camada opcional. Os valores foram aceites pelo utilizador a 2026-11-04 ([P-21](../pendencias.md)); são um gosto, não uma "verdade de moda":

- **Neutras:** branco, cru, bege, caqui, castanho, cinzento, cinzento-escuro, preto, azul-marinho, ganga, prateado e dourado (`ReferenceColor.isNeutral`). Uma cor fora da lista de referência é neutra com croma OKLCH < 0,05. Conta a cor dominante de cada peça (a de maior proporção).
- **Base neutra:** todas as peças grandes (top, parte de baixo, peça única, camadas) com cor dominante neutra.
- **Um só destaque:** exatamente uma peça (calçado incluído) com uma cor não neutra em pelo menos 25 % dela.
- **Tons próximos:** duas ou mais peças grandes, todas com cor (croma ≥ 0,03, o que exclui preto, branco e cinzento) e matizes num arco de 30°.
- **Contraste (2026-11-06):** entre as cores dominantes de duas ou mais peças grandes, pela luminosidade OKLab. **Claro com escuro** se a mais clara e a mais escura estiverem a pelo menos 0,5 (branco ou bege com azul-marinho, cinzento com preto); **contraste suave** se estiverem a no máximo 0,15 (bege com caqui, azul-marinho com preto). Branco com ganga fica no meio. O calçado e os acessórios não contam.
- **Sem cor indicada numa peça:** a combinação fica por saber. Não se descreve nem conta para preferências.
- **Ordem:** as combinações só pesam com uma preferência "Gosto"/"Evito" de combinação (Estilo › Preferências, nas ocasiões dela): +1 ou −1, somado às preferências das peças, com a nota da preferência no conjunto. Sem preferência, aparecem só como descrição ("Cores: base neutra").
- **Padrões e texturas:** padrão por indicar ou liso não conta. Cada padrão além do primeiro, e cada textura forte (marcada ou com pelo) além da primeira, soma um ponto de "competição". O conjunto fica atrás de outro igual em tudo o resto, com a nota "Mais de um padrão: podem competir". Nunca é excluído nem conta como aviso.
- **Formalidade (2026-11-06):** uma peça descontraída e outra arranjada no mesmo conjunto (ex.: sweatshirt com calças de fato) põem-no atrás de outro igual em tudo menos nas preferências, com a nota "Uma peça descontraída com outra arranjada: podem não ligar". Casual cuidado liga com as duas; formalidade por indicar não conta. Nunca é excluído nem conta como aviso. A ocasião pede formalidade só às peças sem ocasiões marcadas (ver “Obrigatório”).
- **Limite:** os pares continuam a ser a i-ésima peça de cada papel. A harmonia ordena estes conjuntos, mas não procura outros pares.

As notas do conjunto aparecem em "Sugestões para hoje". Só o papel em falta fica a laranja escuro, à vista; as outras ficam em "Porquê este".

Ainda não: acessórios. A diversidade na semana (peças repetidas e o mesmo visual em dias seguidos) é do [planeamento](planeamento-semanal.md).

### Montar com o que tenho (2026-11-06)

- `SuggestionRequest.look` (`LookTarget`): o visual de uma inspiração como alvo. Vem das etiquetas confirmadas (paleta, formalidade, padrões, texturas, proporções pelo corte e comprimento das peças) e das peças que o FashionCLIP achou mais parecidas com a imagem ([inspirações](inspiracoes-e-estilo.md)).
- **Peça:** os aspetos em comum (cor, formalidade, padrão, textura, proporções, imagem) entram na ordem de cada papel logo depois da rotatividade e antes das preferências, com a nota `LookMatch` ("Como na inspiração: …").
- **Conjunto:** depois de completos e de menos avisos, primeiro o que soma mais aspetos; só depois as preferências. Os avisos e as regras obrigatórias ficam como no dia.
- Só ordena peças que existem: a inspiração nunca é posse nem cria peças.

## Objetivo

Gerar conjuntos completos e justificáveis apenas com o inventário do utilizador. Não prometer “harmonia perfeita” nem delegar regras obrigatórias a um modelo probabilístico.

## Entradas

Snapshot de peças/atributos, disponibilidade, histórico confirmado, reservas, políticas, ocasião, data/fuso, meteorologia com frescura e preferências.

Um atributo tem valor e origem: indicado pelo utilizador, extraído de imagem ou importado/confirmado. Confiança de extração não equivale a certeza do material.

## 1. Selecionar modelos de composição

Exemplos: top principal + parte inferior + calçado; peça única + calçado; variantes com camadas e acessórios.

Categorias não fixam papéis. T-shirt pode preencher o top principal sem layer exterior. Uma peça física não se repete em dois papéis na mesma composição.

## 2. Aplicar restrições

| Restrições obrigatórias | Preferências/pontuação |
|---|---|
| Posse, atividade e disponibilidade | Paleta, contraste e gosto |
| Papéis necessários e não duplicação | Equilíbrio de padrões/texturas |
| Bloqueios explícitos do utilizador | Diversidade e menor repetição |
| Políticas em modo estrito | Adequação subjetiva/conforto |
| Restrições contextuais configuradas | Preferência por conjuntos guardados |

Uma preferência de cor não pode recuperar uma peça suja. A classificação concreta de limites de conforto depende da política aprovada.

## 3. Representar aparência

### Cores

Extrair uma paleta pequena com proporções e permitir confirmação. Uma fotografia com fundo dominante pode produzir cores erradas; recorte ou seleção manual prevalece.

OKLab/OKLCH é um candidato para distância/contraste percetual. Proximidade no espaço de cor **não significa** boa combinação estética.

Pontuar relações propostas: base neutra, cores dominantes/acento e contraste desejado. Ponderar área visível/importância: a relação entre top e calças tende a pesar mais do que um detalhe pequeno de um acessório.

### Padrões e texturas

Separar padrão (`plain`, riscas, xadrez, etc.), escala/densidade e textura superficial (lisa, canelada, malha aparente, etc.). Regras iniciais conservadoras reduzem competição visual, mas não proíbem misturas universalmente.

### Material e conforto

Composição conhecida ajuda a interpretar cuidado/conforto, mas algodão, lã ou sintético não determinam isoladamente a temperatura adequada. Espessura, construção, cobertura e camadas importam.

## 4. Gerar sem produto cartesiano total

1. Filtrar candidatos por papel/contexto.
2. Começar pelas escolhas fixadas ou pelo papel mais restrito.
3. Acrescentar peças gradualmente.
4. Rejeitar cedo violações e candidatos dominados.
5. Manter um número limitado de composições diversas.
6. Calcular pontuação explicável e razão de exclusões relevantes.

Não enumerar indiscriminadamente todas as combinações do guarda-roupa.

## 5. Pontuar

Combinação ponderada de compatibilidade de cor, padrões/texturas, ocasião, conforto, preferência pessoal e diversidade. Pesos não aprovados não devem surgir no código como uma “verdade de moda”.

Usar uma seed controlável para desempates e regressões. Dado o mesmo snapshot, políticas e seed, o resultado deve ser reproduzível.

Calibrar com exemplos revistos pelo utilizador. “Nunca usou esta sugestão” não é feedback negativo.

## 6. Resultado

Devolver candidatos com peças/papéis, score por componente, razões legíveis, exceções e estado de pesquisa:

- Resultado válido encontrado.
- Resultado parcial para o período.
- Nenhum candidato encontrado dentro do orçamento.
- Dados insuficientes ou restrições incompatíveis conhecidas.

Esgotar pesquisa heurística não prova impossibilidade matemática. Explicar o limite e permitir nova tentativa/ajuste sem inventar uma solução.

## Tecnologia e alternativas

Implementação Dart pura, tipos imutáveis e dependências injetadas de contexto/tempo. Isolar trabalho pesado quando medido; na Web usar estratégia real de worker se necessária.

| Opção | Avaliação |
|---|---|
| Regras + scoring + pesquisa limitada | Recomendado: offline, explicável e sem custo por chamada |
| Regras fixas apenas | Bom início, mas limitado para equilibrar várias preferências |
| Aleatório filtrado | Útil como baseline, fraco para estética e semana |
| Solver exato | Pode provar melhor certas restrições, mas tem custo de modelação/execução |
| LLM remoto | Custos, privacidade e resultados não garantidos; não é motor obrigatório |
| Embeddings/modelo local | Futuro auxiliar de semelhança/estilo; continua a respeitar regras |

## Ações e aceitação

O utilizador confirma atributos, avalia propostas e aprova os limites comportamentais. Não precisa de uma chave de IA.

E2E-03, E2E-05, E2E-08 e E2E-18 do [plano](../plano-e2e.md): composição válida, t-shirt sem camada extra, exclusão de indisponíveis, cores desconhecidas explícitas, diversidade e limitação honesta.

Justificação transversal: [ADR-005](../decisoes/005-motor-de-recomendacao.md).
