# Design e fluxos

Estado: **visual "fio" v2 aprovado pelo utilizador a 2026-11-05** ([proposta com os ecrãs](https://claude.ai/artifact/CP7pHDPqsatzGsJzPn3Tqr), privada). Tema aplicado na app; os ecrãs Hoje, Armário e Peça são redesenhados um a um (ver [roadmap](roadmap.md)).

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
