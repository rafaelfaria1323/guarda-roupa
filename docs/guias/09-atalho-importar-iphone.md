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
   completion(JSON.stringify({ fio: 1, url: location.href, title: document.title, ld, meta }));
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

O mesmo atalho serve para inspirações, sem mudar nada:

1. No Safari, abre o Pin (ou a publicação). Na app do Pinterest: ⋯ → **Copiar link** e abre-o no Safari.
2. **Partilhar → Importar para o fio**. A notificação diz "Inspiração enviada para o fio".
3. No fio, em **Estilo**, aparece um cartão "Do atalho · Pinterest":
   - **Só o link:** guarda o link, o título e a descrição;
   - **Com imagem:** o fio não vai buscar a imagem ao Pinterest. Antes, guarda-a no iPhone (no Pinterest: ⋯ → **Transferir imagem**) e escolhe-a na galeria. A cópia fica privada, só na tua conta;
   - **×:** descarta.

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

O que o atalho manda só tem dados da página do produto: o link, o título, os dados estruturados e as meta tags. Não tem cookies nem nada da tua conta na loja. O fio guarda a pré-visualização na caixa até a usares ou descartares (no máximo 7 dias); da chave só guarda uma impressão digital (hash).
