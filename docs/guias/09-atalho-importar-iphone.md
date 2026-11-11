# Atalho do iPhone: importar de lojas que bloqueiam

Algumas lojas (Zara, Massimo Dutti) bloqueiam a leitura automática dos links ([estado por loja](../features/importacao-de-links.md#estado-por-loja-uso-real)). Com este atalho, és tu a abrir a peça no Safari. O atalho manda para o fio os dados que a página já mostra. Não se contorna nada: a loja não recebe pedidos do fio.

A peça fica à espera no fio durante 7 dias, em **Enviadas pelo atalho**. O Armário avisa quando há alguma.

Só é preciso criar o atalho uma vez (cerca de 5 minutos).

## Antes: a chave do atalho

1. No fio: **Adicionar peça → Importar de um link →** ícone do iPhone, no canto (**Atalho do iPhone**).
2. Toca em **Criar chave**. Aparecem a **chave** e o **endereço**. A chave só se mostra agora: deixa este ecrã aberto até acabares o atalho (ou cria outra mais tarde).

A chave só serve para pôr peças na tua caixa. Se o iPhone se perder, toca em **Desligar** ou **Nova chave**.

## Criar o atalho

1. **Definições → Apps → Atalhos → Avançado**: ligar **Permitir executar scripts** (em inglês: *Allow Running Scripts*).
2. Na app **Atalhos**, toca em **+** e dá-lhe o nome **Importar para o fio**.
3. Toca no **i** (Detalhes) e liga **Mostrar na folha de partilha** (*Show in Share Sheet*). No primeiro bloco ("Receber … da Folha de partilha"), toca nos tipos e deixa só **Páginas web do Safari** (*Safari web pages*).
4. Adiciona a ação **Executar JavaScript na página web** (*Run JavaScript on Web Page*):
   - toca em "Página web" e escolhe **Entrada do atalho** (*Shortcut Input*), que deve ficar azul;
   - apaga o texto que lá está e cola este:

   ```js
   let total = 0;
   const ld = [];
   for (const s of document.querySelectorAll('script[type="application/ld+json"]')) {
     const t = s.textContent;
     if (ld.length < 10 && total + t.length <= 190000) { ld.push(t); total += t.length; }
   }
   const meta = [...document.querySelectorAll('meta[content]')]
     .map(m => [m.getAttribute('property') || m.getAttribute('name') || '', m.getAttribute('content')])
     .filter(([k]) => /^(og:|twitter:|product:|description$)/i.test(k))
     .map(([k, v]) => [k.slice(0, 100), v.slice(0, 2000)])
     .slice(0, 80);
   // Num Pin, junta a imagem que a página mostra (reduzida).
   const load = src => new Promise((ok, no) => {
     const i = new Image();
     i.crossOrigin = 'anonymous';
     i.onload = () => ok(i);
     i.onerror = () => no(new Error('não carregou'));
     i.src = src;
   });
   const pinimg = s => typeof s === 'string' && s.startsWith('https://i.pinimg.com/');
   const seen = el => {
     const r = el.getBoundingClientRect();
     const w = Math.min(r.right, innerWidth) - Math.max(r.left, 0);
     const h = Math.min(r.bottom, innerHeight) - Math.max(r.top, 0);
     return r.width >= 120 && w > 0 && h > 0 ? w * h : 0;
   };
   const pinCandidates = () => {
     const out = [];
     for (const i of document.querySelectorAll('img[elementtiming*="MainPinImage"]')) {
       out.push(i.currentSrc || i.src);
     }
     // A og:image só conta se for deste Pin (ao navegar no feed fica a antiga).
     const ogUrl = (meta.find(([k]) => k.toLowerCase() === 'og:url') || [])[1] || '';
     const og = (meta.find(([k]) => k.toLowerCase() === 'og:image') || [])[1];
     const id = (location.pathname.match(/\/pin\/(?:[^/]*--)?(\d+)/) || [])[1];
     if (!ogUrl || (id && ogUrl.includes(id))) out.push(og);
     // Senão, a maior imagem (ou capa de vídeo) do Pinterest no ecrã.
     const shown = [...document.images].map(i => [i.currentSrc || i.src, seen(i)])
       .concat([...document.querySelectorAll('video[poster]')].map(v => [v.poster, seen(v)]))
       .filter(([s, a]) => pinimg(s) && a > 0)
       .sort((x, y) => y[1] - x[1]);
     for (const [s] of shown.slice(0, 2)) out.push(s.replace(/\/(236x|474x|564x)\//, '/736x/'));
     return [...new Set(out.filter(pinimg))];
   };
   const pinImage = async () => {
     if (!/(^|\.)pinterest\.[a-z.]+$/.test(location.hostname)) return {};
     const list = pinCandidates();
     if (list.length === 0) {
       const all = [...document.images].filter(i => (i.currentSrc || i.src).includes('pinimg')).length;
       return { why: `sem imagem: ${document.images.length} img, ${all} pinimg, ${meta.length} meta` };
     }
     let why = '';
     for (const src of list.slice(0, 3)) {
       try {
         // Pede uma cópia nova: a que o Safari já tem não se deixa ler.
         const fresh = src + (src.includes('?') ? '&' : '?') + 'fio=1';
         const i = await load(fresh).catch(async () =>
           load(URL.createObjectURL(await (await fetch(fresh, { cache: 'no-store' })).blob())));
         const k = Math.min(1, 1280 / Math.max(i.naturalWidth, i.naturalHeight));
         const c = document.createElement('canvas');
         c.width = Math.round(i.naturalWidth * k);
         c.height = Math.round(i.naturalHeight * k);
         c.getContext('2d').drawImage(i, 0, 0, c.width, c.height);
         return { image: c.toDataURL('image/jpeg', 0.8).split(',')[1] };
       } catch (e) {
         why = String((e && (e.name + ' ' + e.message)) || e);
       }
     }
     return { why };
   };
   pinImage().catch(e => ({ why: String(e) })).then(r =>
     completion(JSON.stringify({
       fio: 1, url: location.href, title: document.title, ld, meta,
       image: r.image, imageWhy: r.why && r.why.slice(0, 60),
     })));
   ```

5. Adiciona **Obter conteúdo do URL** (*Get Contents of URL*):
   - no URL, cola o **endereço** do fio;
   - toca na seta (**>**) e escolhe **Método: POST**;
   - em **Cabeçalhos** (*Headers*), adiciona `x-fio-key` com a **chave** como valor;
   - em **Corpo do pedido** (*Request Body*), escolhe **Ficheiro** (*File*) e, como ficheiro, **Resultado do JavaScript** (*JavaScript Result*).
6. Adiciona **Mostrar notificação** (*Show Notification*) e põe como texto o **Conteúdo do URL** (*Contents of URL*). É aí que o fio responde, por exemplo "Enviada para o fio: CASACO EM PELE."

### Sem chave: copiar e colar

Em vez dos passos 5 e 6, adiciona **Copiar para a área de transferência** (*Copy to Clipboard*) com o "Resultado do JavaScript". Depois, no fio: **Adicionar peça → Importar de um link → Colar do atalho**. Também funciona colar o texto no campo do link e carregar em "Ler a página".

Para ficar com cara de app na folha de partilha: no topo do atalho, toca no nome e escolhe **Mudar o nome** para **fio** e **Escolher ícone** (cor e símbolo). Na folha de partilha do Safari, desliza a linha de apps até ao fim, toca em **Mais → Editar** e põe o atalho nos **Favoritos** para aparecer em primeiro lugar.

## Usar

1. No Safari, abre a página **de uma peça** (não uma lista nem a página inicial).
2. **Partilhar → Importar para o fio**. Na primeira vez, o iPhone pergunta se o atalho pode aceder ao site e ao fio: **Permitir**.
3. Aparece a notificação "Enviada para o fio".
4. Abre o fio: a peça entra sozinha no Armário, com o nome, a marca, a primeira foto, as cores (pelo nome da cor na loja, ou pela foto sem o fundo) e o link nas notas. A categoria vem do nome ou da categoria da loja ("Outro" se não souber). Abre o cartão para corrigir o que estiver mal. Podes mandar várias seguidas.

## Pins do Pinterest e publicações do Instagram

O mesmo atalho serve para inspirações:

1. No Safari, abre o Pin (ou a publicação). Na app do Pinterest: ⋯ → **Copiar link** e abre-o no Safari.
2. **Partilhar → Importar para o fio**. A notificação diz "Inspiração enviada para o fio".
3. No fio, em **Perfil** (inspirações), aparece um cartão "Do atalho · Pinterest", já com a imagem do Pin:
   - **Só o link:** guarda o link, o título e a descrição;
   - **Com imagem:** abre a inspiração já com a imagem. A cópia fica privada, só na tua conta;
   - **×:** descarta.

### A imagem do Pin (2026-11-10, corrigido a 2026-11-11)

O script do passo 4 traz a imagem dos Pins. **Se colaste o script antes de 2026-11-11 (segunda correção)**, abre o atalho na app Atalhos, apaga o texto da ação "Executar JavaScript na página web" e cola o script de cima outra vez. O resto do atalho não muda.

Na segunda correção, o script deixou de depender só da `og:image` (que fica a antiga quando se anda de Pin em Pin no feed): usa a imagem principal do Pin, a maior imagem do Pinterest no ecrã ou a capa de um vídeo.

A primeira versão (2026-11-10) não chegava a trazer a imagem: o Safari reaproveitava a imagem que já tinha mostrado, e essa não se deixa ler. E, quando vinha, o fio recusava-a porque a caixa "Por importar" só aceitava 64 kB (agora aceita até 1 MB).

Como funciona: é o teu Safari, na página do Pin que abriste, que lê a imagem que a página mostra (o Pinterest deixa as páginas dele lerem as suas imagens), a reduz (até 1280 pontos) e a manda junto. O fio continua sem pedir nada ao Pinterest. Só para o Pinterest: no Instagram vem só o link.

A notificação do atalho diz se a imagem veio:

- "Inspiração enviada para o fio, com a imagem: …": está tudo bem.
- "… A imagem do Pin não veio (motivo).": manda-me o motivo que aparece. Sem motivo, o atalho ainda tem o script antigo.

Se o cartão aparecer sem imagem, "Com imagem" pede-a como antes: guarda-a no iPhone (no Pinterest: ⋯ → **Transferir imagem**) e escolhe-a na galeria.

## Se não funcionar

| O que acontece | O que fazer |
|---|---|
| O atalho não aparece em Partilhar | Confirmar o passo 3 ("Mostrar na folha de partilha" e "Páginas web do Safari") |
| Erro "não é permitido executar scripts" | Passo 1 |
| Erro "a entrada não é uma página web" | No passo 4, "Página web" tem de ser a Entrada do atalho |
| A notificação diz "Enviada para o fio", mas o Armário não mostra a peça | Fecha a app de vez e abre-a outra vez. Em Importar de um link, ↻ mostra as que estejam à espera |
| "A chave do atalho não é válida" | A chave foi trocada ou desligada. Cria uma nova no fio e põe-na no cabeçalho `x-fio-key` |
| "Já tens 20 peças por importar" | Usa ou descarta algumas em Enviadas pelo atalho |
| "O atalho não mandou a página" | No passo 5, o corpo tem de ser Ficheiro com o Resultado do JavaScript |
| O fio diz "O que está copiado não veio do atalho" | Correr o atalho outra vez na página da peça. Outra cópia pelo meio apaga a do atalho |
| O fio diz "A página não tem os dados do produto" | A loja mudou a página; mandar o link para afinar |

O que o atalho manda só tem dados da página do produto: o link, o título, os dados estruturados e as meta tags (e, num Pin, a imagem). Não tem cookies nem nada da tua conta na loja. O fio guarda a pré-visualização na caixa até a usares ou descartares (no máximo 7 dias); da chave só guarda uma impressão digital (hash).
