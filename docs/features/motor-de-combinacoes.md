# Feature — Motor explicável de combinações

Estado: recomendado para o MVP; regras finas, pesos e limites de pesquisa a calibrar.

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
