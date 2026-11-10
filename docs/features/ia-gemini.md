# Feature — Gemini (opcional): ler fotos e “Pedir ao stylist”

Estado: implementado a 2026-11-06 (pedido do utilizador: menos algoritmos próprios para manter, usando a quota grátis do Gemini). Fica **desligado** até o utilizador o ligar. Falta guardar a chave do Gemini nos secrets e experimentar com fotos reais.

## Decisão

- O Gemini é **só uma opção**. A app funciona igual sem ele: com ele desligado, sem chave no servidor, sem rede ou sem quota, segue pelo que já faz neste aparelho ([IA local](ia-local.md) e cores pela foto).
- O motor de sugestões e o planeador da semana **continuam a base**: no aparelho, sem custo e sem rede. O stylist é um botão a mais, por baixo da sugestão do motor (2026-11-06).
- O Gemini só **sugere**. Tudo fica por confirmar antes de guardar, e há sempre "Desfazer".

## O que faz

Ligar em **Definições › IA local › Gemini (opcional) › Usar o Gemini neste aparelho**. A opção é por aparelho e serve para as fotos e para o stylist.

| Onde | O que o Gemini lê | Se falhar |
|---|---|---|
| **Várias peças de uma vez** | Categoria, nome curto (pt-PT, sem marca), até 3 cores com a proporção, padrão, textura, aquecimento e formalidade | Segue pela categoria do FashionCLIP e pelas cores da foto. Sem chave, sem quota ou fora da lista, avisa uma vez e as restantes fotos seguem sem o Gemini |
| Peça: **Preencher pela foto (Gemini)** (com uma foto) | O mesmo, a partir da capa. Muda a categoria e as cores; o nome e os atributos só se estiverem vazios | Mensagem; o formulário fica como estava |
| Peça: **Ler a etiqueta (Gemini)** | Abre o ecrã [Ler etiqueta](#ecrã-ler-etiqueta-2026-11-10). Lavagem (máquina 30/40/60, à mão, lavandaria), máquina de secar, composição e outros cuidados, em pt-PT, a partir de 1 a 3 fotos da mesma etiqueta | Mensagem no próprio ecrã, a dizer o que fazer; as fotos da etiqueta nunca se guardam |

A foto ao espelho (ver o que se vestiu) ficou de fora por decisão do utilizador (2026-11-06).

## Ecrã "Ler etiqueta" (2026-11-10)

Pedido do utilizador: não se percebia como usar, e as etiquetas das Levi's 501 davam sempre "não se conseguiu ler", mesmo com o Gemini ligado. Causas prováveis: a foto era do rótulo de couro ou da etiqueta do tamanho (não da etiqueta de cuidados, que está cosida por dentro e dobrada em várias páginas), só cabia uma foto e o modelo mais leve falhava na letra miúda.

- **Ecrã próprio, escuro como uma câmara:** os 3 passos em cima (onde está a etiqueta de cuidados e que não é o rótulo de couro nem a do tamanho; desdobrar e boa luz; aproximar e tirar uma foto de cada lado ou página), a câmara ao vivo no meio com uma moldura "Põe a etiqueta aqui", e em baixo **Da galeria**, o botão redondo para tirar a foto e **Ler N fotos**.
- **Até 3 fotos** da mesma etiqueta, vão juntas num só pedido (gasta 1 da quota da app). Cada miniatura tem um "x" para a tirar.
- **O Gemini diz o que viu** (`found`): a etiqueta de cuidados, só o rótulo da marca ou do tamanho, ou nada. Nos dois últimos, o ecrã explica o que procurar e limpa as fotos; se viu a etiqueta mas não a leu, pede para chegar mais perto ou tirar mais uma foto. Só fecha quando há algo lido, e o formulário mostra-o para confirmar (com "Desfazer").
- **Modelo mais forte para etiquetas:** `gemini-flash-latest` (secret `GEMINI_LABEL_MODEL` para trocar). Se esse falhar por quota ou indisponível, a função tenta o modelo de sempre. As fotos das peças continuam no modelo leve.
- **Sem câmara ao vivo** (navegador sem permissão, sem câmara): o ecrã avisa e o botão redondo abre a câmara do sistema; a galeria funciona sempre.
- Câmara pelo pacote `camera` (no navegador, `getUserMedia`, câmara de trás, a maior resolução que der). Código: `lib/features/photo_ai/presentation/label_scan_screen.dart` e `lib/features/photo_ai/application/label_camera.dart` (troca-se nos testes).

## Pedir ao stylist (2026-11-06)

Em **Hoje**, por baixo do cartão das sugestões, aparece o cartão **Ideia do stylist** com o botão **Pedir ao stylist** quando o Gemini está ligado (desenho em [Cartão do Stylist](../design-e-fluxos.md#cartão-do-stylist-v3-aplicado)).

1. A app manda **só texto**: as peças disponíveis (não arquivadas, sem estar a lavar), cada uma com categoria, nome, cores, padrão, textura, aquecimento, formalidade, corte, comprimento, ocasiões, chuva/vento e quantas vezes se usou nos últimos 30 dias. Junta a ocasião escolhida, o tempo (sensação, chuva, vento, sol), as preferências ("gosto"/"evito") e as 20 inspirações mais recentes, só com as etiquetas confirmadas (título, cores, formalidade, padrões, texturas, ocasiões, proporções). O Gemini puxa o conjunto para essa linha quando serve para o dia. Nunca vão fotos, imagens ou links das inspirações, marcas, preços nem notas. Até 150 peças, as menos usadas primeiro; os ids são curtos (`p1`, `p2`…) e só a app sabe a que peça correspondem.
2. O Gemini escolhe um conjunto (cada peça com o papel: top, camada, casaco, parte de baixo, peça única, calçado, acessório), dá-lhe um nome curto e explica porquê em pt-PT.
3. A função só aceita ids que foram mandados. A app volta a verificar: papéis que a categoria permite, um só top/parte de baixo/calçado (um segundo top de malha passa a camada), parte de cima e de baixo ou peça única. Se não servir, diz "não montou um conjunto completo" e não mostra nada. Os avisos do dia (chuva, frio, peça a precisar de limpeza) são os do motor (`DailyEngine.assess`).
4. Depois: **Vestir isto** (abre "Vesti hoje" com as peças por confirmar; só guardar conta como uso), **Guardar como conjunto** (com o nome do stylist), **Outra ideia** (manda a anterior para não a repetir) e **Pedir mudança** ("mais arranjado", "sem ténis"), que ajusta a ideia atual.
5. Se falhar (sem chave, sem quota, sem rede), aparece a mensagem e a sugestão do motor continua lá em cima.

**Um look assim** (2026-11-06): em **Montar com o que tenho**, por baixo dos conjuntos do motor, aparece **Pedir ao stylist um look assim**. A inspiração vai como alvo (`target`, as mesmas etiquetas) e o Gemini tenta que o conjunto fique o mais parecido possível, sem esquecer o tempo; no "porquê" diz o que bate certo e o que muda. Se a inspiração tiver uma só ocasião, é essa a que vai. O resto (verificação, botões, falhas) é igual.

- **App:** `lib/features/stylist/` (`StylistBrief`, `reviewStylistReply`, `SupabaseStylist`, `StylistSection`).
- **Função `stylist`** (`supabase/functions/stylist/`): valida o pedido (2 a 200 peças, até 20 inspirações e um alvo, campos conhecidos, texto curto) antes de gastar quota, usa a mesma quota (`claim_photo_ai_quota`) e responde com um esquema JSON. O código comum com `describe-photo` está em `supabase/functions/_shared/gemini.ts`.

## Peças que faziam falta

No Resumo do armário, o Gemini sugere peças a comprar com marcas e uma pesquisa para cada uma. Ver [peças que faziam falta](pecas-em-falta.md).

## Privacidade e limites

- O stylist e as ideias de compra só recebem texto: das peças (as ideias de compra também com a marca) e das etiquetas das inspirações, nunca fotos, imagens, links ou notas.
- A foto do aparelho só quando o utilizador adiciona fotos ou toca num botão do Gemini, e só com a opção ligada. Não fica guardada no servidor da app.
- Na versão grátis da API, a Google pode usar o conteúdo para melhorar os produtos dela. O ecrã das Definições pede para evitar fotos com pessoas.
- Limite da app: 60 pedidos por hora e 300 por dia por pessoa, somando fotos e stylist (`claim_photo_ai_quota`). A quota grátis do Gemini muda com o tempo e por modelo; quando acaba, a função responde "busy" e a app avisa.

## Como funciona

- **App:** `lib/features/photo_ai/`. `SupabasePhotoReader` manda a foto principal (JPEG ≤ 1600 px) em base64 para a Edge Function `describe-photo`, com a sessão; nas etiquetas, até 3 fotos em `images`. A opção guarda-se em `local_settings` (`gemini_photos`).
- **Função `describe-photo`** (`supabase/functions/describe-photo/`):
  1. Valida o pedido (tipo, base64, ≤ 1,5 MB por foto; 1 foto nas peças, 1 a 3 nas etiquetas) antes de gastar quota.
  2. Pede à base a quota (`claim_photo_ai_quota`). A base confirma a sessão e a allowlist.
  3. Chama o Gemini com a resposta presa a um esquema JSON e `temperature: 0`. Nas etiquetas usa o modelo mais forte e, se falhar por quota ou indisponível, o de sempre.
  4. Devolve só valores que a app conhece: categorias, cores de referência, padrões… O resto vem `null`.
- **Chave:** secret `GEMINI_API_KEY` no GitHub. O workflow "Supabase" passa-a aos secrets da função; sem ele, a função responde 503 e a app usa o que tem. O modelo é `gemini-flash-lite-latest` (o alias segue a versão atual) e muda-se com o secret da função `GEMINI_MODEL`, sem mexer no código. As etiquetas usam `gemini-flash-latest` (secret `GEMINI_LABEL_MODEL`).
- Os registos da função só têm o estado HTTP, nunca a foto nem a chave.

Dados em [modelo de dados](../modelo-de-dados.md#leitura-de-fotos-com-o-gemini-2026-11-06).

## Criar a chave (uma vez, o utilizador)

1. Em [Google AI Studio](https://aistudio.google.com/apikey), entrar com a conta Google e **Create API key**. Não é preciso ativar faturação: sem faturação fica no nível grátis.
2. No GitHub do repositório: **Settings › Secrets and variables › Actions › New repository secret**. Nome `GEMINI_API_KEY`, valor a chave. Não colar a chave em mais lado nenhum (chat, código, notas).
3. Correr o workflow "Supabase" (Actions › Supabase › Run workflow) ou esperar pelo próximo merge na `main`.
4. Na app: **Definições › IA local › Usar o Gemini neste aparelho**. Passa a haver leitura de fotos e **Pedir ao stylist** em Hoje.

Para trocar ou revogar a chave: apagá-la no AI Studio e guardar a nova no mesmo secret.
