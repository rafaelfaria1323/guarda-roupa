# Design e fluxos

Estado: **visual "fio" v2 aprovado pelo utilizador a 2026-11-05** ([proposta com os ecrãs](https://claude.ai/artifact/CP7pHDPqsatzGsJzPn3Tqr), privada). Tema e ecrãs Hoje, Armário e Peça aplicados na app (ver [roadmap](roadmap.md)).

## Nome e logótipo

- **Nome: fio** (escolhido a 2026-11-05 entre trama, Cabide, fio e Roupeiro). Escreve-se sempre em minúsculas. O fio que se cruza no tecido e liga as peças ao plano da semana.
- **Logótipo:** um fio que desenha um "f", com um ponto. Em código: `FioMark` e `FioWordmark` (`lib/app/fio_mark.dart`). Ícone: traço branco sobre índigo, gerado em `web/icons/` (incluindo `apple-touch-icon.png`, 180 px), `web/favicon.png` e `android/.../mipmap-*/ic_launcher.png`.
- O pacote Dart (`guarda_roupa`), o `applicationId` (P-15) e o repositório mantêm o nome antigo: mudá-los partiria o login Android e os dados instalados.

## Direção visual

**Diário pessoal, não loja.** As fotos dão a cor; a interface fica calma. A v1 (fundo neutro, botões pretos, grelha de cartões) foi recusada por parecer uma loja.

- Peças recortadas e pousadas sobre o fundo, com sombra suave, em vez de cartões de produto.
- Frases em vez de números soltos ("Vestiste-os 12 vezes, a última há 6 dias").
- Um botão principal por ecrã (verde salva, em pílula); ações secundárias como texto sublinhado.
- Estados de lavandaria como um ponto e uma palavra ("a lavar"), não como cartões.

**v3 (2026-11-06): design do Stitch.** A pessoa desenhou a app no Google Stitch (ecrãs claros e escuros: Hoje, Armário, Peça, Conjuntos, Semana, Lavandaria, Stylist e Perfil). A fase 1 aplica as cores, a letra e as formas; a disposição de cada ecrã segue em PRs próprios, só com funções que a app já tem.

Tokens (`lib/app/theme.dart`, `AppColors`), claro / escuro:

| Token | Claro | Escuro | Uso |
|---|---|---|---|
| Fundo (linho) | `#FBF9F2` | `#111410` | Ecrãs |
| Superfície | `#FFFFFF` | `#1D201C` | Cartões, campos, barra de navegação |
| Superfície discreta | `#EFEEE7` | `#282B27` | Fundos secundários |
| Texto principal | `#1B1C18` | `#E6E8E1` | Texto |
| Texto secundário | `#5B5F57` | `#B4B7AC` | Metadados |
| Destaque (verde salva) | `#51604B` / texto `#FFFFFF` | `#BCCCAC` / texto `#27341E` | Botão principal, etiquetas escolhidas, separador ativo |
| Destaque suave | `#E2ECDA` / texto `#3C4B37` | `#3D4737` / texto `#D8E8C7` | Indicador do separador |
| Contorno / separador | `#D9D6CC` / `#ECE7DE` | `#454840` / `#2C2F2A` | Pílulas, contorno de cartões e campos |
| Lavandaria (terracota) | `#D9A78F` / texto `#7D5541` | `#EFBBA2` | "a lavar", "a secar" |

Cartões brancos com 16 de raio e contorno de 1 px; botões, etiquetas e pesquisa em pílula. Um teste confirma o contraste do texto nos dois temas.

Letra: **Manrope** em tudo (títulos a 600–700, mais apertados). OFL, incluída como assets estáticos em `assets/fonts/` (gerados com `tool/fonts/instance_fonts.py`). Não depender só da cor para comunicar estados.

## Ecrã Hoje (v3, aplicado)

`PlannerScreen` segue o ecrã "home_dashboard" do Stitch (2026-11-06), só com o que a app já faz. De cima para baixo:

1. **Data e saudação.** A barra mostra `FioWordmark`. Por cima do título, a data em maiúsculas pequenas ("SEXTA-FEIRA, 6 DE NOVEMBRO"); o título é "Bom dia." / "Boa tarde." / "Boa noite." conforme a hora.
2. **Tempo numa caixa branca** (resumo da previsão, origem e hora em letra pequena; "Atualizar" e "Indicar o tempo à mão" como ações discretas).
3. **Cartão do look do dia.** Começa com um ponto verde e "Sugestões para hoje" e a ocasião numa linha de pílulas que desliza. Depois vem a sugestão como flat-lay: as peças (`GarmentCutout`: foto com borda branca e sombra; sem foto, um cartão na cor principal da peça) pousadas com rotações pequenas. Por baixo, "Sugestão 1 de N", os nomes numa frase e os avisos (lavagem, rotação, papel em falta) a laranja escuro. As razões ficam atrás de "Porquê este".
4. **Botões do cartão.** "Vou vestir isto" ocupa a largura e abre "Vesti hoje" com as peças por confirmar. Ao lado há dois botões redondos:
   - guardar como conjunto, com a ocasião escolhida e sem a camada opcional;
   - mostrar outro, que passa à sugestão seguinte e, no fim, pede um novo lote ao motor.

   Uma sugestão que já é um conjunto guardado diz "Um dos teus conjuntos" a verde, por baixo dos nomes, e não mostra o botão de guardar. Com uma peça trocada diz "De um dos teus conjuntos, com Preta em vez de Azul" e o botão fica (guarda a variante como outro).
5. **Pedir ao stylist** (só com o Gemini ligado): ver [Cartão do Stylist](#cartão-do-stylist-v3-aplicado).
6. **Atalhos**: três cartões iguais com um círculo verde-claro: "Adicionar peça", "Novo conjunto" e "Planear a semana" (abre o separador Semana).
7. **Lavandaria**, só quando há peças por lavar, a lavar, a secar ou na limpeza: "2 peças na lavandaria", as primeiras pelo nome e "Ver" (abre o cesto).
8. **Vesti hoje.** Sem registo: uma linha e o botão "Vesti hoje". Com registo: "Hoje vestiste" com as peças recortadas, "Corrigir" e "Desfazer".

A semana passou para o separador Semana ([planeamento semanal](features/planeamento-semanal.md)).

Os textos longos de ajuda (o que conta como uso, as regras da semana) saíram do ecrã; as regras continuam nas features.

## Cartão do Stylist (v3, aplicado)

`StylistSection` segue o ecrã "ai_stylist" do Stitch (2026-11-06) num cartão próprio por baixo da sugestão do motor (e em "Montar com o que tenho"), sem percentagens de harmonia, marcas, "regressa à rotação" nem looks alternativos. Antes de pedir: estrela num círculo verde-claro, "Ideia do stylist", a explicação curta e "Pedir ao stylist" a toda a largura. Depois:

1. A ideia como no look do dia (colagem, nome do stylist e as peças).
2. O porquê do stylist numa caixa com aspas.
3. "Vou vestir isto" e, ao lado, os botões redondos de guardar como conjunto e outra ideia — iguais aos do cartão de cima.
4. "Pedir mudança" por baixo.

## Ecrã Armário (v3, aplicado)

`WardrobeScreen` segue o ecrã "wardrobe_gallery" do Stitch (2026-11-06), sem marca, tamanho, preço nem favoritos. De cima para baixo:

1. Título "Armário" na barra e uma frase com o total: "8 peças · 2 a lavar ou a secar" (a segunda parte só aparece quando há peças nesse estado).
2. Pesquisa em pílula branca (nome, marca ou notas) e, numa linha que desliza, os filtros: "Todas (8)", cada tipo com quantas peças tem ("Tops (3)"), disponibilidade, ocasião e "Arquivadas" no fim. As contas são do Armário todo, sem arquivadas.
3. **Grelha de cartões**, dois por linha num telemóvel (mais em ecrãs largos). Cada cartão tem a peça recortada (`GarmentCutout`) num fundo de linho, em 4:5, e por baixo:
   - o tipo em maiúsculas pequenas e, à direita, quantas vezes foi usada ("3× usada", "nunca usada");
   - o nome;
   - o material, quando está preenchido.
4. Sobre a foto, só quando foge ao normal, um selo com um ponto e uma palavra: a laranja para "A lavar", "A secar" e "Lavar recomendado"; a cinzento para outras disponibilidades e "Arquivada". "Disponível" não se escreve.
   Peças iguais aparecem uma vez, com o selo "×N" e, se nem todas estiverem disponíveis, "2 de 3 disponíveis"; tocar abre uma folha com cada unidade (estado e última vez vestida) e "Juntar mais uma igual" ([peças iguais](features/guarda-roupa.md#peças-iguais)).
5. Botão "Adicionar peça" em pílula verde, com o texto à vista.

As prateleiras por tipo (v2) saíram: os filtros com contagem fazem o mesmo trabalho.

## Ecrã Peça (v3, aplicado)

Tocar numa peça abre a ficha em **modo de ver** (`GarmentDetailScreen`, `/guarda-roupa/peca/:id`); mudar os dados é em "Editar" (`/guarda-roupa/peca/:id/editar`, o formulário de sempre). Segue o ecrã "clothing_details" do Stitch (2026-11-06), sem marca nova, tamanho, preço nem favoritos. De cima para baixo:

1. A peça recortada em grande, ligeiramente rodada, num quadrado de linho com cantos redondos; no canto, um selo com o estado ("Disponível", "A lavar", "Lavar recomendado"…).
2. Um cartão com tipo · marca · "Arquivada" em maiúsculas pequenas, o nome (ou o tipo, sem nome) e as cores em círculos; com material, as cores e o material ficam numa faixa de linho.
3. Três números em cartões: **Vezes usada**, **Última vez** ("há 6 dias", "nunca") e **Até lavar** ("2 usos", "Lavar já" a laranja, ou "—" sem regra de lavagem).
4. "Onde está": a disponibilidade em chips, que muda logo ao tocar (sem passar pelo formulário).
5. "Últimas vezes": as últimas 5 utilizações como um fio (data e com que peças foi).
6. "Vou vestir hoje": abre o registo de utilização com a peça já escolhida (não aparece em peças arquivadas).

Guardar no formulário volta à ficha; duplicar abre o formulário da cópia; arquivar e eliminar voltam ao Armário.

## Ecrã Conjuntos (v3, aplicado)

`OutfitsScreen` segue o ecrã "outfit_collection" do Stitch (2026-11-06), sem favoritos, temperatura nem sugestões do stylist. De cima para baixo:

1. "Conjuntos" na barra e o total: "3 conjuntos guardados".
2. Filtros por ocasião com contagem ("Todos (3)", "Casual (2)"), só com as ocasiões que algum conjunto tem.
3. Um **cartão por conjunto**:
   - colagem com até três peças recortadas (a primeira em grande, as outras empilhadas) e o selo "3 peças";
   - o nome (ou as primeiras peças) e as ocasiões num selo à direita; com nome, as peças por baixo;
   - "Usado 2 vezes · há 6 dias" (conta os dias em que todas as peças do conjunto foram vestidas juntas) ou "Ainda não usado", e "Incompleto" quando falta uma peça base;
   - aviso a laranja quando há peças que não estão disponíveis;
   - "Vou vestir hoje" (abre o registo com as peças já escolhidas) e "Editar".
4. Botão "Novo conjunto" em pílula verde.

## Ecrã Montar conjunto (v3, aplicado)

`OutfitEditorScreen` (novo ou editar) segue o ecrã "outfit_builder" do Stitch (2026-11-06), sem percentagem de harmonia, temperatura ideal, marcas nem notas do stylist. De cima para baixo:

1. Nome (opcional) e ocasiões em chips.
2. Cartão **Composição**: selo "Tudo disponível" ou "1 peça não está disponível"; as peças escolhidas em grelha de duas colunas, cada uma com a foto recortada, o "×" para tirar, o estado a laranja quando não está disponível ("A lavar") e o papel escolhido por baixo do nome; no fim, "Conjunto completo." ou "Falta: …" e o total de peças.
3. Cartão **Juntar peças**: filtros por grupo (Todos, Tops, Partes de baixo, Calçado…, só os que têm peças) e as peças restantes em grelha de três colunas, com "+" — tocar junta-a com o papel sugerido.
4. "Guardar" e "Eliminar conjunto" ficam na barra de cima.

## Ecrã Semana (v3, aplicado)

`WeekScreen` segue o ecrã "weekly_planner" do Stitch (2026-11-06), sem avisos inventados nem "planear com IA" (o plano já se faz sozinho). De cima para baixo:

1. O mês em maiúsculas pequenas, "A tua semana" e "Planear de novo".
2. **Faixa dos sete dias**: dia da semana, número, o tempo previsto (ícone e graus) e um nó com a cor da peça principal (tracejado se por decidir); hoje a verde. Tocar num dia leva ao seu cartão.
3. **Um cartão por dia**: data, "HOJE", o tempo e o estado num selo; a ocasião (lista com "A decidir"); "Pode não acontecer"; as peças recortadas, umas por cima das outras, com os nomes; avisos e propostas como antes; "Aceitar", "Alterar", "Deixar vazio" e, hoje, "Vesti isto hoje" em botão verde.

## Navegação

Cinco separadores, como no design v3 (2026-11-06):

- **Hoje:** saudação, tempo, sugestão do dia e "Vesti hoje".
- **Armário:** peças por tipo, pesquisa, estados de lavandaria.
- **Conjuntos:** composições guardadas e ocasiões.
- **Semana:** o plano dos próximos dias, que se enche sozinho.
- **Perfil:** a conta, um resumo (peças, conjuntos, inspirações), a entrada para Definições e o estilo (inspirações e preferências).

Conta, sincronização e backup em definições, com estado de sync visível também nos contextos relevantes. Em ecrãs largos, substituir navegação inferior por lateral sem criar outra aplicação.

## Ecrãs necessários

| Ecrã | Conteúdo e ações |
|---|---|
| Entrada/conta | Login, estado da sessão e recuperação apropriada ao método |
| Onboarding | Cidade, preferências essenciais, políticas e informação sobre sync |
| Catálogo | Peças, disponibilidade, pesquisa e filtros |
| Adicionar/editar peça | Foto, categoria, cores e preenchimento progressivo |
| Detalhe da peça | Histórico, disponibilidade, política e utilização em conjuntos |
| Hoje | Conjunto planeado, alterações efetivas e “Usei este conjunto” |
| Semana | Dias, ocasiões, reservas, escolhas fixadas e avisos |
| Conjunto guardado | Composição, papéis e ocasiões |
| Lavandaria | Avisos, peças sujas/em lavagem/a secar e transições explícitas |
| Inspirações | Foto/link, etiquetas e preferências confirmadas |
| Alterações propostas | Comparação antes/depois e confirmação |
| Sync/conflitos | Pendências, erros e resolução sem perda silenciosa |
| Dados/backup | Exportação, recuperação, espaço e limites |

## Fluxos principais

### Registar uma peça

1. Escolher adicionar manualmente, com fotografia ou link.
2. Capturar/selecionar e recortar quando necessário.
3. Confirmar categoria e cores; permitir restantes campos desconhecidos.
4. Guardar localmente e mostrar se o upload ainda está pendente.
5. Confirmar estado sincronizado quando dados e media tiverem sido aceites.

### Planear e utilizar

1. Selecionar dias e ocasiões ou aplicar uma rotina configurada.
2. Gerar proposta com justificações e exceções.
3. Ajustar/fixar escolhas e aceitar o plano.
4. No dia, confirmar as peças realmente utilizadas, idealmente num toque.
5. Se o dia não foi cumprido, manter pendente ou marcar como não utilizado; não inferir gosto.

### Cuidar da roupa

1. Mostrar aviso de lavagem baseado em utilizações confirmadas.
2. Utilizador pode indicar que a peça precisa de limpeza.
3. Avançar para lavagem e secagem conforme o processo real.
4. Confirmar limpeza e disponibilidade sem saltos automáticos de tempo.

### Rever uma alteração

Mudou a previsão ou uma peça ficou indisponível: destacar os dias afetados, explicar a causa e propor substituições. Não aplicar antes da confirmação nem reescrever o histórico.

## Estados que não podem faltar

Sem inventário; inventário incompleto; sem candidatos; pesquisa limitada; sem rede; previsão antiga; upload pendente; quota atingida; sessão expirada; conflito; operação cancelada; recuperação inválida.

O estado vazio não deve parecer um erro de rede, nem um erro parecer “não tens roupa”.

## Acessibilidade e atrito

Alvos de toque adequados, navegação por teclado na Web, labels semânticas e tamanhos de texto escaláveis. Testar contraste, foco e leitura de estados.

Evitar exigir dezenas de campos por peça. Não obrigar a introduzir todo o guarda-roupa antes de experimentar sugestões, mas explicar os limites de um inventário incompleto.

## Alternativas e motivo

| Opção | Avaliação |
|---|---|
| Material 3 personalizado | Recomendado: componentes acessíveis e manutenção previsível |
| UI totalmente desenhada de raiz | Maior liberdade, mas maior custo em acessibilidade e consistência |
| Kit visual de terceiros | Pode acelerar, mas aumenta dependências/licenças e pode limitar adaptação |
| Calendar package complexo | Desnecessário para sete cartões e um conjunto diário no início |

Os wireframes concretos e o número final de tabs precisam de aprovação no incremento UX.
