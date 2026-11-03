# Feature — Planeamento semanal

Estado: necessária no MVP de planeamento; um conjunto por dia inicialmente.

## Objetivo

Escolher uma semana coerente, não apenas repetir sete chamadas independentes ao gerador diário.

## Entradas e estado

Datas locais, ocasiões por dia, previsão identificada, preferências, peças disponíveis, histórico, políticas, escolhas fixadas e reservas existentes.

Cada entrada tem composição própria e estado: proposta, aceite, confirmada como utilizada ou não utilizada. Um plano aceite não equivale a sete utilizações.

## Algoritmo recomendado

1. Obter candidatos diários do [motor](motor-de-combinacoes.md).
2. Ordenar a pesquisa por dias mais restritos, sem perder a cronologia necessária à rotatividade.
3. Expandir estados semanais, considerando usos projetados e escolhas fixadas.
4. Penalizar repetições evitáveis e premiar diversidade sem violar restrições.
5. Manter um conjunto limitado de estados promissores, por exemplo com beam search.
6. Devolver a melhor semana encontrada dentro do orçamento e a qualidade/limites da pesquisa.

Quando a expansão não for cronológica, validar intervalos em ambas as direções e reavaliar o calendário completo. Não basta um contador incremental dependente da ordem de visita.

Limites de candidatos, largura da pesquisa e tempo serão escolhidos na POC de desempenho. Não prometer ótimo global.

## Reservas, roupa escassa e lavagem

Reservas influenciam apenas planeamento. Não alteram utilizações reais nem contagem de lavagens.

Roupa já suja continua excluída. Não preencher um dia futuro presumindo uma lavagem que ainda não aconteceu.

Se não houver sete opções nas políticas atuais, devolver dias válidos e explicar os restantes. Uma repetição permitida é identificada; não enfraquecer uma regra estrita em segredo.

Se o inventário for pequeno, o sistema adapta-se em vez de exigir mais peças para usar a app.

## Mudanças posteriores

Uma peça ficou suja ou a previsão mudou:

1. Identificar entradas afetadas.
2. Explicar porquê.
3. Propor substituições, preservando escolhas fixadas.
4. Mostrar diferença entre plano atual e proposta.
5. Aplicar só após confirmação.

Uma confirmação real corrige o histórico e pode tornar reservas futuras desadequadas. Isso origina avisos, não reescrita automática.

## Tecnologia e alternativas

Dart puro, snapshots e resultados tipados. Planos e composições em Drift/sync. UI Flutter com cartões por dia; não necessita de um calendário complexo no MVP.

| Opção | Avaliação |
|---|---|
| Pesquisa conjunta limitada | Recomendado: equilibra semana com custo controlado |
| Sete escolhas greedy independentes | Baseline simples; pode gastar cedo a única peça de outro dia |
| Busca exaustiva | Escala mal com volume/atributos |
| Solver exato | Reavaliar se as restrições justificarem complexidade extra |

## Ações e aceitação

O utilizador define rotina/ocasiões, fixa opções e aceita alterações. Datas e ocasiões não devem ser inventadas como decisões pessoais.

E2E-05, E2E-07 e E2E-09 do [plano](../plano-e2e.md): semana com opções escassas, sapatos reutilizados, reservas sem uso, escolhas fixadas e mudanças pendentes de aceitação.

Referências: [ADR-005](../decisoes/005-motor-de-recomendacao.md), [modelo](../modelo-de-dados.md).
