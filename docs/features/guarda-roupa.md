# Feature — Guarda-roupa e peças

Estado: necessária no MVP. Implementação recomendada nos incrementos 1–2.

Implementado (2026-11-03): criar/editar/duplicar/arquivar/eliminar (tombstone, com confirmação e limpeza das fotos), disponibilidade, pesquisa sem acentos, filtros por grupo de categoria e disponibilidade, categoria escolhida à mão ou, com o modelo de IA local, entre as 3 sugeridas pela foto ([IA local](ia-local.md#poc-implementada-2026-11-04)), cores de uma paleta de 26 cores de referência, com Prateado e Dourado para metais e Verde-menta, Turquesa, Terracota e Lilás (2026-11-06), com proporção aproximada (passos de 5%, soma ≤ 100%; abaixo de 10% é um detalhe; confirmadas pelo utilizador; podem ser sugeridas pela foto e ficam marcadas até confirmar, ver [fotografias](fotografias-e-ficheiros.md)) e fotografias. Detalhes opcionais (secção “Detalhes”; nada escolhido = “não sei”): padrão, textura superficial, aquecimento, adequação a chuva e vento (sim/não/não sei), formalidade (descontraído, casual cuidado ou arranjado; 2026-11-06), corte (justo, normal, largo) e comprimento (curto, normal, comprido) (2026-11-06; servem as proporções das inspirações), ocasiões iniciais (casual, trabalho (smart casual), noite/saída; também como filtro da lista), lavagem (máquina 30°/40°/60°, à mão, limpeza profissional) e máquina de secar (2026-11-06; servem o [cesto da roupa](lavandaria.md)) e material/cuidados como texto da etiqueta. Ecrã Armário (design do Stitch, 2026-11-06): grelha de cartões com a peça, o estado quando foge ao normal, o tipo, quantas vezes foi usada e o material; filtros por tipo com contagem ([design](../design-e-fluxos.md#ecrã-armário-v3-aplicado)). Ficha da peça em modo de ver (uso, disponibilidade em chips, últimas vezes, "Vou vestir hoje"), com "Editar" para o formulário ([design](../design-e-fluxos.md#ecrã-peça-v2-aplicado)). [Várias peças de uma vez](#várias-peças-de-uma-vez-2026-11-06) a partir de fotos da galeria, com categoria e cores sugeridas (2026-11-06). [Peças iguais](#peças-iguais) (2026-11-06): criar várias de uma vez, vê-las juntas no Armário e escolher o grupo no “Vesti hoje”. Acessórios por tipo (2026-11-06): cachecol, gorro, luvas, chapéu ou boné, óculos de sol, chapéu-de-chuva, cinto, mala ou mochila e outro acessório (gravata, meias, joias...); os que já existiam ficam como “outro acessório”. A sugestão do dia junta os que fazem sentido com o tempo ([motor](motor-de-combinacoes.md#acessórios-pelo-tempo-2026-11-06)). Por fazer: composição estruturada (percentagens por fibra). Os símbolos de cuidados já se leem pela foto com o Gemini (ecrã Ler etiqueta, 2026-11-10).

## Várias peças de uma vez (2026-11-06)

Pedido do utilizador (tornar a app mais automática). No Armário, o ícone de galeria abre **“Várias peças de uma vez”**:

- Escolhem-se até 20 fotos da galeria, uma por peça. Cada foto passa a uma peça logo ali, como se fosse criada à mão (a foto conta para a quota e sincroniza).
- **Categoria:** a mais provável pela foto, com a IA local ([FashionCLIP](ia-local.md)); sem o modelo neste aparelho, “Outra”. A seguir mostram-se as 3 mais prováveis em chips: um toque muda, e “Outra…” abre a lista toda.
- **Cores:** da miniatura, sem o fundo quando há o modelo de recorte; ficam por confirmar, como nas cores sugeridas no formulário.
- **Com o Gemini ligado** ([Gemini](ia-gemini.md)): cada foto vem também com um nome curto, as cores e os atributos lidos pelo Gemini; se falhar, segue como acima.
- Fotos que não servem (HEIC, formato desconhecido, demasiado grandes) ficam na lista com o motivo e não criam peça.
- Tocar na foto abre a peça para o resto (nome, marca, detalhes). “Concluir” volta ao Armário.

Código: `BatchAddScreen`, `addPhotoAsGarment` (`lib/features/wardrobe/`).

No formulário da peça, com o Gemini ligado, há também **Preencher pela foto** e **Ler a etiqueta**, que abre um ecrã com a câmara ao vivo e os passos a seguir (2026-11-10; [Gemini](ia-gemini.md#ecrã-ler-etiqueta-2026-11-10)).

## Objetivo e dados

Representar peças físicas, não apenas produtos comerciais. Cada unidade tem ID, categoria, disponibilidade, histórico e fotografias próprios.

Campos progressivos:

| Grupo | Informação |
|---|---|
| Identificação | Nome opcional, categoria, marca/origem opcionais |
| Aparência | Cores e proporções, padrão, textura superficial |
| Contexto | Ocasiões, formalidade, aquecimento/cobertura, adequação conhecida a chuva/vento |
| Composição | Material e cuidados quando conhecidos, preferencialmente pela etiqueta |
| Operação | Disponibilidade, arquivo, políticas específicas e imagens |

Padrão, textura e composição não são o mesmo atributo. “Malha” visível não prova percentagem de lã.

## Comportamento

1. Criar uma peça com informação essencial e completar depois.
2. Corrigir sugestões de categoria/cor antes ou depois de guardar.
3. Pesquisar/filtrar por categoria, disponibilidade e contexto.
4. Arquivar peças sem perder histórico.
5. Duplicar dados de uma peça semelhante, criando um novo ID e histórico vazio (as fotografias copiam-se, ver [Peças iguais](#peças-iguais)).
6. Mostrar dados guardados localmente e estado da sincronização.

Não exigir um número conhecido de peças nem impor um limite de 100. Uma peça sem dados suficientes pode existir no catálogo; o motor explica eventuais limitações para a usar.

## Procurar a peça no Google Lens (2026-11-10)

Na ficha de uma peça com foto, por baixo de "Vou vestir hoje", o botão **Procurar no Google Lens** abre o Lens com a foto da peça, para ver onde se vende ou encontrar parecidas. Detalhes e privacidade em [inspirações](inspiracoes-e-estilo.md#procurar-no-google-lens-2026-11-10).

## Peças iguais

Várias unidades da mesma peça (ex.: três t-shirts brancas iguais) continuam a ser **peças distintas**: cada uma tem id, disponibilidade, utilizações, lavagens e rotação próprias ([produto](../produto.md)). O que muda é só a forma de as criar e mostrar:

- **Criar:** no formulário de peça nova, “Quantas tens iguais?” (1 a 10) cria essas peças de uma vez, com os mesmos dados e as mesmas fotos.
- **Duplicar** (menu da peça) e **“Juntar mais uma igual”** criam mais uma unidade e copiam as fotografias com ids novos: cada uma pode depois ter as suas, e apagar uma não apaga as da outra. Uma foto que só está no Storage descarrega-se (com verificação do SHA-256); sem rede fica de fora.
- **Iguais** = mesma categoria, nome e marca (sem contar maiúsculas e espaços), mesmas cores, os mesmos detalhes e o mesmo estado de arquivo (`GarmentTwins`). Uma peça sem nome nem cores fica sempre sozinha. Não há coluna nova: o grupo calcula-se.
- **Armário:** o grupo aparece uma vez, com “×N” e, se nem todas estiverem disponíveis, “2 de 3 disponíveis”. Tocar abre a lista das unidades, com o estado e a última vez que foi vestida; tocar numa abre a sua ficha. Mudar o nome ou a cor de uma unidade separa-a do grupo.
- **“Vesti hoje”:** o grupo é uma só linha; escolhê-lo regista a unidade disponível há mais tempo sem uso (nunca vestida primeiro; empate: a mais antiga). Desmarcar tira qualquer unidade do grupo.

## Tecnologia

Flutter/Material 3, Riverpod e repositório de guarda-roupa. Drift para queries/transações; Supabase e motor de sync se aprovados. As fotografias usam o [subsistema de media](fotografias-e-ficheiros.md).

Índices apenas para consultas usadas; miniaturas na grelha; paginação/carregamento incremental conforme o volume. Não carregar originais para preencher cartões pequenos.

## Alternativas e escolha

| Opção | Avaliação |
|---|---|
| Modelo relacional tipado | Recomendado: histórico, relações e queries consistentes |
| Documento JSON único por guarda-roupa | Simples no início, mas conflitos e atualizações amplas em sync |
| Formulário obrigatório muito extenso | Dados mais completos, mas manutenção pouco realista |
| Só fotografia e IA | Menos input inicial, mas erros/atributos desconhecidos; inadequado como única fonte |
| Scanner de código de barras | Depende de catálogo externo e variantes; adiado |

Ver [ADR-002](../decisoes/002-repositorios-estado-e-dados.md).

## Falhas e ações humanas

Peça sem fotografia pode usar placeholder identificado. Falha de guardar não pode resultar num cartão de sucesso. Falha do upload mantém estado pendente e possibilidade de retomar.

O utilizador confirma atributos que a app não conhece. Configurações externas só são necessárias na fundação: [ambiente](../guias/01-ambiente-macos.md) e [cloud](../guias/02-supabase-projeto-e-storage.md).

## Aceitação comportamental

E2E-01, E2E-11 e E2E-18 do [plano E2E](../plano-e2e.md): criar, editar, arquivar, reabrir, usar offline e sincronizar; duas unidades iguais mantêm históricos distintos; testar 10/50/100 peças sem transformar esses números em limites.
