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
- Um botão principal por ecrã (índigo, em pílula); ações secundárias como texto sublinhado.
- Estados de lavandaria como um ponto e uma palavra ("a lavar"), não como cartões.

Tokens (`lib/app/theme.dart`, `AppColors`):

| Token | Valor | Uso |
|---|---|---|
| Fundo (papel) | `#F3F0EA` | Ecrãs |
| Superfície | `#FFFFFF` | Cartões, campos, barra de navegação |
| Superfície discreta | `#EAE6DE` | Fundos secundários |
| Texto principal | `#1E1F24` | Texto, etiquetas selecionadas |
| Texto secundário | `#5C5E66` | Metadados |
| Destaque (índigo, o fio) | `#3446C9` | Botão principal, separador ativo, logótipo |
| Destaque suave | `#ECEEF9` / texto `#26349A` | Indicador do separador, etiquetas |
| Contorno / separador | `#D5D0C6` / `#E4DFD5` | Pílulas por selecionar, divisões |
| Lavandaria | `#D9822B` / texto `#8A4B12` | "a lavar", "a secar" |

Letra: **DM Sans** no texto e na interface; **Fraunces** (serifada) só em títulos grandes. Ambas OFL, incluídas como assets estáticos em `assets/fonts/` (geradas com `tool/fonts/instance_fonts.py`). Não depender só da cor para comunicar estados.

## Ecrã Hoje (v2, aplicado)

De cima para baixo, sem cartões à volta (`PlannerScreen`):

1. **Marca e saudação.** A barra mostra `FioWordmark`; o título é "Bom dia." / "Boa tarde." / "Boa noite." conforme a hora (Fraunces, 40).
2. **Tempo numa frase** (resumo da previsão, origem e hora em letra pequena; "Atualizar" e "Indicar o tempo à mão" como ações discretas).
3. **Sugestão do dia como flat-lay.** As peças (`GarmentCutout`: foto com borda branca e sombra; sem foto, um cartão na cor principal da peça) pousadas com rotações pequenas. Por baixo, "Sugestão 1 de N", os nomes numa frase e os avisos (lavagem, rotação, papel em falta) a laranja escuro. As razões ficam atrás de "Porquê este".
4. **Ocasião** numa só linha de pílulas que desliza na horizontal.
5. **Um botão principal**, "Vou vestir isto" (abre "Vesti hoje" com as peças por confirmar), "Mostrar outro" (passa à sugestão seguinte; no fim pede um novo lote ao motor) e "Guardar como conjunto" (com a ocasião escolhida, sem a camada opcional). Uma sugestão que já é um conjunto guardado diz "Um dos teus conjuntos" a índigo, por baixo dos nomes, e não mostra o botão; com uma peça trocada diz "De um dos teus conjuntos, com Preta em vez de Azul" e o botão fica (guarda a variante como outro).
6. **Vesti hoje.** Sem registo: uma linha e o botão "Vesti hoje". Com registo: "Hoje vestiste" com as peças recortadas, "Corrigir" e "Desfazer".
7. **A tua semana como um fio** (`WeekThread`): sete nós com a cor da peça principal de cada dia (vestida, senão planeada); tracejado = por decidir; hoje com contorno. Por baixo, os dias em cartões brancos com a ocasião, "Pode não acontecer", as peças e as ações (inalterados).

Os textos longos de ajuda (o que conta como uso, as regras da semana) saíram do ecrã; as regras continuam nas features.

## Ecrã Armário (v2, aplicado)

`WardrobeScreen`, de cima para baixo:

1. Título "Armário" na barra e uma frase com o total: "8 peças · 2 a lavar ou a secar" (a segunda parte só aparece quando há peças nesse estado).
2. Pesquisa em pílula branca (nome, marca ou notas) e, numa linha que desliza, os filtros: tipo, disponibilidade, ocasião e "Arquivadas" no fim.
3. **Sem filtros:** prateleiras por tipo (Tops, Partes de baixo, Calçado…), cada uma com o título, quantas peças tem e as peças recortadas (`GarmentCutout`) numa linha que desliza. "Ver todas" (com mais de 3 peças) filtra por esse tipo.
4. **Com pesquisa ou filtros:** as mesmas peças em grelha.
5. Cada peça mostra o nome e, só quando foge ao normal, um ponto e uma palavra: a laranja para "A lavar", "A secar" e "Lavar recomendado"; a cinzento para outras disponibilidades e "Arquivada". "Disponível" não se escreve.
   Peças iguais aparecem uma vez, com o selo "×N" e, se nem todas estiverem disponíveis, "2 de 3 disponíveis"; tocar abre uma folha com cada unidade (estado e última vez vestida) e "Juntar mais uma igual" ([peças iguais](features/guarda-roupa.md#peças-iguais)).
6. Botão "Adicionar peça" em pílula índigo, com o texto à vista (mais claro do que só "+").

## Ecrã Peça (v2, aplicado)

Tocar numa peça abre a ficha em **modo de ver** (`GarmentDetailScreen`, `/guarda-roupa/peca/:id`); mudar os dados é em "Editar" (`/guarda-roupa/peca/:id/editar`, o formulário de sempre). De cima para baixo:

1. A peça recortada em grande, ligeiramente rodada, e "Editar" na barra.
2. Nome (ou o tipo, sem nome) e, por baixo, tipo · marca · "Arquivada".
3. Uma frase sobre o uso: "Usada 3 vezes, a última há 6 dias." e, com regra de lavagem, "Mais 2 usos e pede lavagem." ou "Pede lavagem." a laranja.
4. "Onde está": a disponibilidade em chips, que muda logo ao tocar (sem passar pelo formulário).
5. "Últimas vezes": as últimas 5 utilizações como um fio (data e com que peças foi).
6. "Vou vestir hoje": abre o registo de utilização com a peça já escolhida (não aparece em peças arquivadas).

Guardar no formulário volta à ficha; duplicar abre o formulário da cópia; arquivar e eliminar voltam ao Armário.

## Navegação

- **Hoje:** saudação, tempo, sugestão do dia, "Vesti hoje" e a semana.
- **Armário:** peças por tipo, pesquisa, estados de lavandaria.
- **Conjuntos:** composições guardadas e ocasiões.
- **Estilo:** inspirações e preferências.

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
