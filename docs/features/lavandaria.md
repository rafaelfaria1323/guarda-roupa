# Feature — Lavandaria e recomendações de cuidado

Estado: necessária no MVP; valores iniciais decididos em P-07 (2026-11-03), editáveis.

## Valores decididos (P-07)

| Grupo | Aviso de lavagem após |
|---|---|
| T-shirts, tops e roupa desportiva | cada utilização |
| Camisas e polos | 2 utilizações |
| Camisolas, calças, ganga, saias e vestidos | 4 utilizações |
| Casacos e calçado | sem aviso |

Contam só utilizações confirmadas (“Vesti hoje”) desde a última limpeza registada. O aviso é informativo: nunca muda a disponibilidade sozinho.

## Dois conceitos separados

| Conceito | Efeito |
|---|---|
| Recomendação de lavar | Aviso informativo baseado em utilizações e política |
| Precisa de limpeza / em lavagem / a secar | Indisponibilidade real; exclui a peça das novas combinações |

**Atingir o limiar recomendado não marca automaticamente uma peça como suja.** Uma opção de automatismo só pode ser ativada de forma explícita, explicando o efeito no planeamento.

## Estados e transições

Fluxo comum: disponível → precisa de limpeza → em lavagem → a secar → disponível. Permitir registar outros processos reais, como lavagem e secagem concluídas numa ação ou limpeza profissional, sem obrigar a passos fictícios.

Uma limpeza confirmada reinicia a contagem relevante, mas a peça só fica disponível quando estiver pronta. Secagem não termina porque passou um temporizador presumido.

A limpeza da peça e o desgaste geral são métricas diferentes.

## Política recomendada

Usar categoria, override da peça, utilizações confirmadas desde a última limpeza e cuidados conhecidos. O utilizador pode indicar manchas, suor/uso intenso ou necessidade imediata.

Não pedir sensores, análises de odor nem inferir higiene por fotografia.

### Referência de partida

A [USU Extension](https://extension.usu.edu/news_sections/home_family_and_food/the-dirt-on-laundry-how-often-to-wash), citando orientações do ACI, apresenta:

| Grupo | Orientação geral publicada |
|---|---|
| T-shirts, roupa de exercício, meias, roupa interior, leggings/collants e fatos de banho | Após cada utilização |
| Vestidos, camisolas, saias, calças, jeans e alguns outros grupos | Aproximadamente 3–4 utilizações |
| Casacos e roupa exterior | Intervalos muito superiores e dependentes do tipo |

Isto **não é um conjunto de defaults já aprovado**, uma garantia sanitária ou autorização para lavar qualquer tecido à máquina. Etiqueta, nódoas, cheiro, intensidade e preferências prevalecem.

Sem histórico anterior, pedir opcionalmente uma situação inicial; “não sei” não equivale a “acabou de ser lavada”.

## Planeamento futuro

Roupa já suja não é candidata. O planeador não assume que será lavada a tempo.

Reservas podem mostrar recomendações previstas, mas não alteram estados reais. Se o utilizador ativar uma política automática de indisponibilidade após uso, esse efeito tem de ser considerado na projeção da semana, sem inventar uma limpeza futura.

Um plano antigo afetado recebe aviso e proposta de alteração; não é reescrito silenciosamente.

## Tecnologia e alternativas

`LaundryPolicy` em Dart puro, eventos e disponibilidade em repositório transacional. Partilha o histórico confirmado da feature de [utilização](utilizacao-e-rotatividade.md).

| Opção | Avaliação |
|---|---|
| Políticas offline editáveis | Recomendado: transparente e sem API paga |
| Um único número para todas as peças | Rejeitado: ignora categorias e cuidados |
| IA a decidir sujidade | Não fiável e desnecessário |
| Disponibilidade automática por defeito | Rejeitada: aviso não prova estado real |

## Ações e aceitação

O utilizador revê recomendações e regista o cuidado real. Nunca é necessário indicar composição exata quando desconhecida.

E2E-06 e E2E-11 do [plano](../plano-e2e.md): limiar apenas avisa; marcar suja exclui; a secar continua excluída; limpeza pronta restaura disponibilidade; confirmação duplicada não duplica contagem; conflitos não apresentam “limpo” silenciosamente.
