# Feature — Utilização real e rotatividade

Estado: necessária no MVP; valores iniciais para roupa a aprovar.

## Requisitos confirmados

Só uma utilização explicitamente confirmada altera histórico, contadores e recomendações de lavagem. Idealmente há um toque diário para confirmar o conjunto realmente usado.

Calçado e acessórios podem repetir para este utilizador. Continuam sujeitos a disponibilidade e restrições contextuais.

## Eventos reais

O utilizador pode confirmar o plano, ajustar as peças efetivamente usadas ou registar uso manual. Uma data ignorada não cria um evento nem um voto negativo de estilo.

A mesma entrada de plano confirmada nos dois dispositivos produz uma única utilização lógica. Retry mantém o ID da operação. Registos manuais independentes não são automaticamente a mesma utilização; prever aviso/correção de duplicados.

Desfazer/corrigir deve recalcular as projeções afetadas de forma consistente.

## Políticas propostas, não defaults aprovados

| Política | Comportamento |
|---|---|
| Intervalo por categoria/peça | Evita reutilização antes da data elegível |
| Preferência por menos usadas | Favorece peças com menos usos recentes |
| Rotação do inventário elegível | Favorece alternativas antes de repetir dentro de um grupo relevante |
| Exceção por falta de alternativas | Só dentro do modo autorizado, com aviso claro |
| Modo estrito | Não ultrapassa intervalo; devolve limitação em vez de uma exceção |

Recomendação inicial: combinar intervalo com preferência por alternativas ainda não utilizadas. Se não houver opção válida, explicar e pedir/usar apenas a exceção previamente autorizada.

“Rodar tudo” refere-se ao inventário elegível para aquele papel/contexto: não obriga a vestir um casaco de inverno no verão antes de repetir uma t-shirt.

## Semântica de datas

Proposta de contrato: `dias mínimos entre datas de utilização`. Exemplo de contrato, **não default**: com valor 3, uma utilização no dia 1 volta a ser elegível no dia 4.

Confirmar esta interpretação em P-06. Calcular com datas de calendário no fuso do plano, não com blocos de 24 horas sujeitos a mudanças de hora.

## Planeamento

Reservas futuras influenciam a semana para não sugerir a mesma peça todos os dias. Não incrementam contadores reais.

O planeador considera histórico real + composições já reservadas, distinguindo ambos na explicação. Uma reserva cancelada deixa de limitar o futuro sem criar um “uso apagado”.

Nunca flexibilizar disponibilidade, posse ou bloqueio explícito só porque não existem alternativas.

## Tecnologia e alternativas

Dart puro para `RotationPolicy`; eventos relacionais em Drift; operação de confirmação transacional e idempotente na cloud.

| Alternativa | Avaliação |
|---|---|
| Histórico de eventos + políticas | Recomendado: correções e explicações verificáveis |
| Contador sem histórico | Insuficiente: não explica datas nem corrige duplicados com segurança |
| Incrementar ao gerar plano | Rejeitado: gera usos fictícios |
| Escolha puramente aleatória | Pode repetir e não respeita intenção; apenas desempate controlado |

## Ações e aceitação

O utilizador aprova valores iniciais/overrides e confirma usos. A app deve mostrar o efeito de uma mudança de política.

E2E-04, E2E-05, E2E-09 e E2E-17 do [plano](../plano-e2e.md): confirmação única, offline, correção, roupa escassa, reserva sem uso, sapatos repetidos e mudança de hora.
