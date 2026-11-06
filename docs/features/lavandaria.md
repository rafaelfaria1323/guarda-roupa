# Feature — Lavandaria e recomendações de cuidado

Estado: necessária no MVP; valores iniciais decididos em P-07 (2026-11-03), editáveis.

## Valores decididos (P-07)

| Grupo | Aviso de lavagem após |
|---|---|
| T-shirts, tops e roupa desportiva | cada utilização |
| Camisas e polos | 2 utilizações |
| Camisolas, calças, ganga, saias e vestidos | 4 utilizações |
| Casacos e calçado | sem aviso |

Contam só utilizações confirmadas (“Vesti hoje”) desde a última limpeza registada.

**Lavandaria sozinha** (decisão do utilizador a 2026-11-06, substitui “nunca muda a disponibilidade sozinho”): ao guardar ou corrigir um “Vesti hoje”, as peças disponíveis que chegam ao limiar passam a **Precisa de limpeza** (`LaundryPolicy.dirtyAfterWear`). O aviso diz quais (“Marquei para lavar: Branca.”), e “Desfazer” anula o uso e devolve-as. Uma peça só volta a Disponível com **Lavei hoje** ou mudando-a à mão; nunca por passar tempo. Como fica indisponível, a semana troca-a sozinha nos dias planeados ([planeamento](planeamento-semanal.md)).

## Implementado (incremento 3)

- Ficha da peça, secção **Lavagem**: utilizações desde a última limpeza, data da última limpeza, aviso “Recomendado lavar” e botão **Lavei hoje** (com desfazer). Desde 2026-11-06, “Lavei hoje” também devolve a peça a Disponível se não estava (desfazer repõe o estado anterior); “A lavar” e “A secar” continuam a poder escolher-se à mão.
- Lista do guarda-roupa: o estado (“Precisa de limpeza”, “A lavar”, “A secar”) ou, numa peça disponível com o limiar mudado depois, “Lavar recomendado”.
- Definições → **Aviso de lavagem por categoria**; cada peça pode ter o seu na ficha. `0` = sem aviso; “Predefinido” volta ao valor da tabela acima.
- Sem limpeza registada contam todas as utilizações registadas (não se presume que a peça acabou de ser lavada). No mesmo dia, conta a ordem de registo entre utilização e limpeza.
- Dados: `cleaning_events` e `care_policies` (uma linha por categoria ou peça, id determinístico; último a escrever ganha, campo a campo), escritos por `apply_wear_operation` (`record_cleaning`, `void_cleaning`, `set_policy`). `care_policies.rotation_days` fica pronto para a rotatividade.
- Backup (desde o formato v2): limpezas e valores escolhidos entram e são recuperados.
- **Nódoa ou uso intenso (2026-11-06):** no “Vesti hoje”, uma peça escolhida tem o botão da gota, “Ficou para lavar já”. Ao guardar, vai para “Precisa de limpeza” mesmo antes do limiar, no mesmo aviso (“Marquei para lavar: …”) e com o mesmo “Desfazer”.
- **Limpeza profissional (2026-11-06):** estado **Na lavandaria** (`at_cleaners`): a peça está fora de casa, numa lavandaria ou limpeza a seco, e não entra nas sugestões. Na ficha, **Levei à lavandaria** marca-a (com desfazer); enquanto lá está, o botão de limpeza passa a **Já veio da lavandaria**, que regista a limpeza e a devolve a Disponível. Se o texto de cuidados da etiqueta pede limpeza a seco ou “não lavar”, a ficha diz “A etiqueta pede limpeza profissional.” (só lê o que foi escrito; não adivinha). Nos conflitos entre dispositivos, fica entre “A lavar” e “Precisa de limpeza”.
- Por fazer: símbolos de cuidados estruturados (hoje é texto livre).

## Dois conceitos separados

| Conceito | Efeito |
|---|---|
| Recomendação de lavar | Aviso informativo baseado em utilizações e política |
| Precisa de limpeza / em lavagem / a secar | Indisponibilidade real; exclui a peça das novas combinações |

Atingir o limiar ao confirmar um uso marca a peça como “Precisa de limpeza” (escolha explícita do utilizador a 2026-11-06). Mudar o limiar depois não muda o estado de nenhuma peça: fica só o aviso.

## Estados e transições

Fluxo comum: disponível → precisa de limpeza → em lavagem → a secar → disponível. Limpeza profissional: precisa de limpeza (ou disponível) → na lavandaria → disponível (“Já veio da lavandaria”). Permitir registar outros processos reais, como lavagem e secagem concluídas numa ação ou limpeza profissional, sem obrigar a passos fictícios.

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
