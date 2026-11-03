# ADR-005 — Motor de recomendação e planeamento

Estado: motor determinístico explicável recomendado; calibração por realizar.

## Contexto

O produto precisa de cumprir regras físicas/operacionais e equilibrar gostos subjetivos, offline e sem custo por chamada. Uma solução esteticamente interessante não pode usar roupa suja ou inexistente.

## Alternativas

| Opção | Benefícios | Limitações | Decisão |
|---|---|---|---|
| Regras + scoring + pesquisa limitada | Explicável, local, reproduzível e incremental | Pesos/regras precisam de calibração; não garante ótimo | Recomendada |
| Lista rígida de combinações | Muito simples e transparente | Não adapta bem inventário, clima e preferências | Baseline parcial |
| Aleatório após filtros | Barato e diverso | Qualidade inconsistente; pouca coerência semanal | Baseline de comparação |
| Solver exato | Pode dar garantias para modelo formal | Modelação/execução e integração Web mais complexas | Rever se houver necessidade |
| LLM remoto | Texto e interpretação flexíveis | Rede, custos, privacidade e violação de constraints | Não como motor obrigatório |
| Modelo local de estilo | Sem inferência paga e útil para semelhança | Pesos/licença/download/precisão | Evolução auxiliar |

## Decisão detalhada

Restrições antes de pontuação. Composições por papéis, atributos explícitos e unknowns preservados. T-shirt pode ser top principal sem outras camadas.

Paletas e padrões são componentes de preferência, não leis universais. OKLab ajuda a medir diferenças percetuais, mas não prova harmonia.

Gerar progressivamente, podar e manter candidatos diversos. O planeador semanal combina candidatos considerando reservas e efeitos cronológicos.

## Explicabilidade

Reason codes estruturados para explicações e testes: peças indisponíveis, repetição, ocasião, conforto, preferência, exceção e limite de pesquisa.

Não guardar apenas uma frase livre ou score total impossível de decompor.

Escolha da seed, políticas, versão do motor e snapshot/contexto permitem reproduzir uma proposta. Não é necessário registar fotografias ou dados privados em logs.

## Consequências

Mais trabalho de definição de regras do que chamar uma API, mas custos previsíveis e controlo. Novos atributos/feedback podem melhorar o motor sem substituir o histórico.

Pesquisa heurística sem resultado não deve ser apresentada como prova de impossibilidade.

## Validação e revisão

Conjunto de exemplos revistos pelo utilizador, constraints verificadas por testes focados e jornadas reais. Comparar qualidade com baseline simples.

Definir dispositivo e orçamento em P-09. Rever algoritmo se os limites impedirem semanas úteis ou quando um solver/modelo demonstrar benefício mensurável.

Detalhes: [motor](../features/motor-de-combinacoes.md), [semana](../features/planeamento-semanal.md), [IA](../features/ia-local.md).
