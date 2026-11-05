# Feature — Planeamento semanal

Estado: necessária no MVP de planeamento; um conjunto por dia inicialmente.

## Implementado (2026-11-04, dados, pesquisa e ecrã)

- Tabela `plan_entries` e `apply_plan_operation` ([modelo](../modelo-de-dados.md)): uma entrada por dia com ocasião, provisório, peças e estado; edições com `base_version` desatualizada ficam como **proposta pendente** (ADR-008), tal como um segundo “criar” para o mesmo dia vindo de outro dispositivo. Aceitar aplica a proposta; rejeitar descarta-a.
- Regras da semana (P-19, `WeekPlanRules`): 7 dias; os dias úteis começam em “Trabalho (smart casual)”, o fim de semana “a decidir” e provisório (pode ficar vazio).
- Um plano nunca conta como utilização: só “Vesti hoje” cria `wear_events`, e a mesma entrada confirmada em dois dispositivos dá uma só utilização (`plan_entry_id`).
- Pesquisa semanal (`WeeklyPlanner`, Dart puro): beam search cronológica sobre os candidatos do motor diário (largura 8, 5 candidatos por dia por omissão).
  - Os dias já escolhidos entram como **utilizações projetadas** (reservas) e a rotatividade de cada dia vê-as. Só servem para planear: não são utilizações nem contam para a lavagem.
  - Roupa indisponível fica de fora; não se presume uma lavagem futura.
  - Ordem explícita, sem pesos: papéis em falta, avisos das peças (rotatividade, lavagem, conforto, ocasião desconhecida, preferência a evitar), peças principais repetidas na semana, soma das posições no motor diário. Empate desfeito pelas peças escolhidas, por isso o mesmo pedido dá a mesma semana.
  - Escolhas fixadas entram tal como estão e contam como reserva. Um dia pode ficar fora da pesquisa (fim de semana vazio).
  - Cada dia diz o estado (`planned`, `pinned`, `skipped`, `notFound` com as lacunas) e que peças principais repete. Uma repetição permitida é identificada, nunca escondida.
  - A ordem é cronológica, por isso as regras de intervalo só precisam de olhar para trás. A pesquisa devolve quantas semanas parciais avaliou: é limitada e não promete o ótimo global.
- Ecrã “Esta semana” em Hoje (antes Planeador) (`WeekPlanCard`): um cartão por dia, de hoje a 6 dias depois, com a ocasião (lista com “A decidir”), “Pode não acontecer” (provisório), as peças e o estado (Por planear, Proposto, Aceite, Vestido, Não usado).
  - “Planear a semana” corre a pesquisa com a previsão de cada dia (o tempo indicado à mão vale para hoje) e grava como **propostos** só os dias ainda não aceites. Dias aceites entram como escolha fixada; aceites vazios ficam fora da pesquisa.
  - Por dia: aceitar, alterar (volta a proposto), deixar vazio (dias provisórios) e, hoje, “Vesti isto hoje”, que abre “Vesti hoje” com as peças por confirmar e liga a utilização à entrada (`plan_entry_id`). Só aí o dia passa a Vestido.
  - Repetições e dias sem conjunto possível aparecem no cartão do dia; uma proposta pendente de outro dispositivo mostra o que muda, com “Aplicar” ou “Manter o atual”.
  - Dias confirmados ou passados não se editam.
- Mudanças posteriores (`PlanReview`, Dart puro): os dias propostos ou aceites são revistos sempre que o guarda-roupa, as utilizações ou a previsão mudam.
  - Problemas por peça: arquivada ou eliminada; indisponível (a lavar, a secar, precisa de limpeza); lavagem recomendada pelas utilizações reais (P-07); aquecimento desadequado à previsão atual; calçado ou casaco que não é para a chuva ou o vento; frio que pede um casaco que o dia não tem.
  - A rotatividade não é um problema: a repetição já foi identificada ao planear.
  - A proposta troca **só as peças com problemas** (as outras são escolhas a preservar) pela primeira do mesmo papel na ordem do motor diário, de preferência sem avisos. As substitutas veem as reservas dos dias anteriores. No frio junta-se um casaco; sem alternativa, a proposta diz que papel fica por escolher.
  - O cartão do dia mostra “Mudou desde o plano”, o porquê e a diferença (“Trocar X por Y”, “Juntar Z”). “Aplicar alteração” grava a troca e mantém a ocasião e o estado. “Manter o plano” esconde a proposta nesta sessão, mas os avisos ficam.
  - Nada se reescreve sozinho. Dias confirmados ou passados não se reveem.

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
