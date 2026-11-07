# Feature — Inspirações e preferências de estilo

Estado: abordagem assistida confirmada; interpretação visual avançada adiada.

## Implementado (incremento 4)

- Separador **Perfil** (antes "Estilo"; desenho em [design](../design-e-fluxos.md#ecrã-perfil-v3-aplicado)): lista de inspirações (título ou domínio do link, etiquetas e paleta) e editor com título, link, notas e etiquetas.
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
- **Preferências** (segundo segmento do separador Perfil): "Gosto" ou "Evito" de uma cor, padrão, textura, formalidade ou combinação (base neutra, um só destaque, tons próximos, claro com escuro, contraste suave).
  - O contexto são as ocasiões em que vale; sem ocasiões, vale sempre.
  - Só pode haver uma preferência ativa para o mesmo assunto, valor e contexto. A app explica quando já existe.
  - Ao editar, o assunto e a origem ficam; mudam o valor, a posição e o contexto.
  - Numa inspiração guardada, **Criar preferências** propõe um "Gosto" por etiqueta (cores, formalidade, padrões e texturas), no contexto das ocasiões dela. O utilizador escolhe quais quer; as repetidas são ignoradas. A preferência guarda a inspiração de origem e fica se a inspiração for eliminada.
  - Não é posse: não cria, não esconde nem altera peças. No motor é só uma componente da ordem de peças que existem: cor, padrão e textura em cada peça, combinação de cor no conjunto ([motor](motor-de-combinacoes.md#conjunto-cores-padrões-e-texturas-2026-11-04)).
- Dados:
  - a tabela `inspirations` é escrita por `apply_style_operation` (`create_inspiration`, `edit_inspiration` campo a campo, `delete_inspiration`, `set_inspiration_image`, `remove_inspiration_image`) e sincronizada pelo stream `user_inspirations`;
  - a tabela `style_preferences` é escrita pela mesma função (`create_preference`, `edit_preference`, `delete_preference`) e sincronizada pelo stream `user_style_preferences`;
  - as duas partilham a fila local `style_operations`.
- **Montar com o que tenho** (2026-11-06): numa inspiração guardada com etiquetas ou imagem, o botão abre conjuntos do motor do dia feitos só com peças próprias e disponíveis, ordenados pelo que têm da inspiração ([motor](motor-de-combinacoes.md#montar-com-o-que-tenho-2026-11-06)). Com o Gemini ligado, **Pedir ao stylist um look assim** pede ao Gemini um conjunto parecido, com a explicação ([Gemini](ia-gemini.md#pedir-ao-stylist-2026-11-06)). O stylist do dia também tem em conta as inspirações.
  - Conta, em cada peça: uma cor parecida com a paleta (OKLab ≤ 0,08, em pelo menos 25 % da peça), a mesma formalidade, um dos padrões, uma das texturas e, com imagem e o FashionCLIP descarregado, ser das mais parecidas com a imagem (das 8 primeiras, no máximo 2 por grupo: tops, partes de baixo, calçado…). Atributo por indicar não conta.
  - Valem as regras de hoje: tempo (previsão ou indicado à mão), ocasião (a da inspiração, se for só uma), rotatividade, lavagem e avisos. A inspiração passa à frente das preferências, não das regras.
  - Cada peça diz porquê ("Como na inspiração: cor, formalidade"). Dá para vestir já ("Vou vestir isto") ou guardar como conjunto, com o nome e as ocasiões da inspiração. "Mostrar outros" troca entre peças equivalentes.
  - Tudo neste dispositivo, sem nuvem. As proporções contam pelo corte e comprimento das peças (por indicar não conta): justo em cima e largo em baixo quer um top justo ou uma parte de baixo larga; tudo justo/largo, tops, partes de baixo, peças inteiras e casacos com esse corte; camada comprida, um casaco comprido; parte de cima curta, um top curto. Um agente na nuvem (Claude) ficou como opção futura, por decidir (privacidade e custo).
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

### Pelo atalho do iPhone (2026-11-06, P-13)

Decisão do utilizador a 2026-11-06: **Partilhar → fio** (não a API oficial) e, para a imagem, **perguntar sempre**.

- **Enviar:** no Safari, com um Pin (ou uma publicação do Instagram) aberto, Partilhar → **Importar para o fio**. É o mesmo atalho das lojas ([guia](../guias/09-atalho-importar-iphone.md)), sem mudanças. A notificação diz "Inspiração enviada para o fio: …".
- **Na função:** uma página de `pinterest.*`, `pin.it` ou `instagram.com` é uma inspiração, não uma peça (`inspiration_sites.ts`). Ficam na caixa do atalho:
  - o link canónico (`og:url`, só se for do mesmo site);
  - o título (`og:title`, sem o "| Pinterest" do fim, até 120 caracteres);
  - a descrição (`og:description`, até 1000 caracteres).

  Partilha a caixa das peças (até 20 envios, 7 dias, a mesma quota). Não autoriza imagens.
- **Nunca se lê o Pinterest:** o robots.txt do Pinterest recusa qualquer leitor automático (`User-agent: *` → `Disallow: /`, verificado a 2026-11-06), e as imagens (`i.pinimg.com`) não têm CORS. Por isso nem a função nem a PWA pedem páginas ou imagens. Um link do Pinterest ou do Instagram colado em Importar de um link não é lido nem gasta quota: a app diz para o partilhar pelo atalho (`inspiration_site`).
- **Na app:** no Perfil › Inspirações, cada Pin à espera aparece num cartão, "Do atalho · Pinterest", com três escolhas:
  - **Só o link:** a inspiração fica logo com o link, o título e a descrição nas notas;
  - **Com imagem:** abre o editor preenchido e pergunta "Guardar uma cópia da imagem?". O fio não a vai buscar: o utilizador transfere-a no Pinterest (⋯ → Transferir imagem) e escolhe-a na galeria. A cópia é privada, com o link de origem, para uso pessoal. O Pin sai da caixa ao guardar; se o utilizador sair sem guardar, o cartão fica;
  - **Descartar** (×).
- **Etiquetas:** como sempre, só as que o utilizador escolhe. O título e a descrição do Pin não geram etiquetas.

### Limites

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
