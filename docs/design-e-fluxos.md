# Design e fluxos

Estado: proposta de UX, sem mockups ou ficheiro Figma criado. Data: 2026-10-31.

## Direção visual

Minimalismo editorial: fotografias como protagonistas, hierarquia tipográfica clara, poucas ações simultâneas e espaço entre elementos.

Usar Material 3 personalizado. Candidatos de tokens, ainda sujeitos a contraste e aprovação:

| Token | Proposta |
|---|---|
| Fundo | `#F6F4EF` |
| Superfície | `#FFFFFF` |
| Texto principal | `#202521` |
| Destaque | `#61745B` |
| Separador | `#DFE3DC` |

Não depender só da cor para comunicar estados. Começar com fontes de sistema; uma fonte incluída como asset só entra após verificar licença e orçamento de download.

## Navegação proposta

- **Planeador:** hoje, semana e confirmação de utilização.
- **Guarda-roupa:** catálogo, filtros e acesso à lavandaria.
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
