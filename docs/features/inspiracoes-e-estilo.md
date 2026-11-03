# Feature — Inspirações e preferências de estilo

Estado: abordagem assistida confirmada; interpretação visual avançada adiada.

## Objetivo

Aproximar sugestões do gosto pessoal sem confundir uma fotografia inspiradora com peças possuídas.

## Primeira versão

1. Adicionar uma imagem própria/autorizada ou guardar um link de referência.
2. Confirmar etiquetas úteis: paleta, nível de formalidade, proporções, padrões/texturas e ocasiões.
3. Indicar preferências explícitas, como gostar de bases neutras ou de um acento.
4. Relacionar a preferência com contexto, sem aplicá-la cegamente a todas as ocasiões.
5. Usar essas preferências na pontuação de conjuntos compostos por peças reais do inventário.

Sem imagem acessível, um link continua a ser um bookmark válido. Não mostrar uma análise visual que nunca aconteceu.

## Pinterest

Guardar URL é viável como referência. Extrair automaticamente imagem, autoria e conteúdo de um Pin depende de permissões e acesso efetivo à plataforma.

Não afirmar que a API permite consultar qualquer link arbitrário. Não contornar autenticação, termos ou proteção anti-bot.

Uma alternativa inicial é carregar manualmente uma imagem cuja utilização seja permitida e manter a origem.

## Tecnologia

`Inspiration`, `StylePreference`, etiquetas tipadas e assets privados; repositórios e sync comuns.

No motor, preferências são componentes de score, nunca autorização para sugerir uma peça não possuída.

Feedback explícito pode ser guardado com motivo. Ausência de confirmação/uso não equivale a desagrado.

## Alternativas

| Opção | Avaliação |
|---|---|
| Etiquetas assistidas e confirmação | Escolhida para começar: transparente, barata e corrigível |
| Importar só URL | Útil, mas não permite prometer análise do conteúdo |
| Questionário inicial extenso | Estruturado, mas com demasiado atrito |
| Embeddings visuais locais | Promissor para semelhança, adiado até haver modelo/licença/POC |
| LLM/visão cloud | Não necessário; privacidade e custo por chamada incompatíveis como dependência obrigatória |

## Falhas e ações

Mostrar imagem indisponível e permitir substituir/reabrir a origem. Não descarregar imagens para um bucket público.

O utilizador confirma etiquetas e direitos de uso. Só é necessária uma conta Pinterest se uma futura integração oficial o exigir; não é pré-requisito do estilo assistido.

## Aceitação

E2E-10 do [plano](../plano-e2e.md): inspiração influencia a preferência sem criar inventário, etiquetas podem ser corrigidas, link sem imagem não produz inferência fictícia e preferências nunca ultrapassam disponibilidade.

Evolução: [IA local](ia-local.md). Pendência: P-13 em [Pendências](../pendencias.md).
