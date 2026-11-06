# Feature — Inspirações e preferências de estilo

Estado: abordagem assistida confirmada; interpretação visual avançada adiada.

## Implementado (incremento 4)

- Separador **Estilo**: lista de inspirações (título ou domínio do link, etiquetas e paleta) e editor com título, link, notas e etiquetas.
- Uma inspiração precisa de um título ou de um link. Um link sem esquema ganha `https://`. Só são aceites links `http(s)`: o servidor e a app recusam `javascript:` e outros esquemas.
- O link é só guardado e pode ser copiado. A app não abre nem analisa a página, e a interface diz isso.
- **Imagem** (opcional, uma por inspiração): câmara ou galeria, com o mesmo processamento das fotos das peças (1600 px + miniatura, sem EXIF/GPS).
  - Antes de abrir a câmara ou a galeria, a app pede confirmação de que a imagem é do utilizador ou autorizada (uma vez por ecrã). Para referências de outras pessoas, guarda-se o link.
  - Fica privada, no bucket `garment-photos` em `{uid}/{image_id}/main.jpg|thumb.jpg` (as mesmas políticas por pasta). As etiquetas continuam a ser só as escolhidas; a imagem nunca gera etiquetas.
  - **Peças parecidas** (2026-11-04, [IA local](ia-local.md)): com o FashionCLIP neste dispositivo, "Procurar peças parecidas" compara a imagem com a capa de cada peça própria e mostra as 5 mais parecidas. É só para olhar e abrir a peça: não liga nada nem muda etiquetas.
  - Numa inspiração nova, a imagem fica pendente e é ligada ao guardar. Numa existente, ligar, trocar e retirar aplicam-se logo.
  - A miniatura aparece na lista em vez da paleta.
  - Os ficheiros sobem antes de o servidor ligar a imagem (`set_inspiration_image`, rejeitado com `missing_file` se faltarem). Trocar é `remove_inspiration_image` + `set_inspiration_image` na mesma transação. Depois de retirar ou eliminar, os ficheiros são apagados do Storage (melhor esforço) e do dispositivo. Um `remove_inspiration_image` atrasado só tira a imagem se ainda for a mesma.
- Etiquetas confirmadas pelo utilizador:
  - paleta: até 8 cores de referência;
  - formalidade: descontraído, casual cuidado ou arranjado;
  - ocasiões, padrões e texturas;
  - proporções: justo em cima e largo em baixo, largo em cima e justo em baixo, tudo justo, tudo largo, camada comprida, parte de cima curta.
  Sem etiquetas, a inspiração mostra "Sem etiquetas", nada é inventado.
- Não é posse: não cria nem referencia peças e não aparece no guarda-roupa.
- **Preferências** (segundo segmento do separador Estilo): "Gosto" ou "Evito" de uma cor, padrão, textura, formalidade ou combinação (base neutra, um só destaque, tons próximos).
  - O contexto são as ocasiões em que vale; sem ocasiões, vale sempre.
  - Só pode haver uma preferência ativa para o mesmo assunto, valor e contexto. A app explica quando já existe.
  - Ao editar, o assunto e a origem ficam; mudam o valor, a posição e o contexto.
  - Numa inspiração guardada, **Criar preferências** propõe um "Gosto" por etiqueta (cores, formalidade, padrões e texturas), no contexto das ocasiões dela. O utilizador escolhe quais quer; as repetidas são ignoradas. A preferência guarda a inspiração de origem e fica se a inspiração for eliminada.
  - Não é posse: não cria, não esconde nem altera peças. No motor é só uma componente da ordem de peças que existem: cor, padrão e textura em cada peça, combinação de cor no conjunto ([motor](motor-de-combinacoes.md#conjunto-cores-padrões-e-texturas-2026-11-04)).
- Dados:
  - a tabela `inspirations` é escrita por `apply_style_operation` (`create_inspiration`, `edit_inspiration` campo a campo, `delete_inspiration`, `set_inspiration_image`, `remove_inspiration_image`) e sincronizada pelo stream `user_inspirations`;
  - a tabela `style_preferences` é escrita pela mesma função (`create_preference`, `edit_preference`, `delete_preference`) e sincronizada pelo stream `user_style_preferences`;
  - as duas partilham a fila local `style_operations`.
- No motor (2026-11-06): as preferências de formalidade contam em cada peça com essa formalidade ([motor](motor-de-combinacoes.md)).
- Backup: inspirações (com proporções, desde a v4, e imagem, desde a v5) e preferências entram e são recuperadas com ids novos ([backups](backups-e-recuperacao.md)).

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
