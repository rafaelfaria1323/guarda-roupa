# Atalho do iPhone: importar de lojas que bloqueiam

Algumas lojas (Zara, Massimo Dutti) bloqueiam a leitura automática dos links ([estado por loja](../features/importacao-de-links.md#estado-por-loja-uso-real)). Com este atalho, és tu a abrir a peça no Safari. O atalho copia os dados que a página já mostra e o fio lê-os. Não se contorna nada: a loja não recebe pedidos do fio.

Só é preciso criar o atalho uma vez (cerca de 3 minutos).

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

5. Adiciona **Copiar para a área de transferência** (*Copy to Clipboard*). Deve ficar com "Resultado do JavaScript".
6. (Opcional) Adiciona **Mostrar notificação** (*Show Notification*) com o texto "Copiado. Abre o fio e carrega em Colar do atalho."

## Usar

1. No Safari, abre a página **de uma peça** (não uma lista nem a página inicial).
2. **Partilhar → Importar para o fio**. Na primeira vez, o iPhone pergunta se o atalho pode aceder ao site: **Permitir**.
3. No fio: **Adicionar peça → Importar de um link → Colar do atalho**. Aparece a pré-visualização habitual: escolhe a variante e as fotos e confirma no formulário.

Também funciona colar o texto no campo do link e carregar em "Ler a página".

## Se não funcionar

| O que acontece | O que fazer |
|---|---|
| O atalho não aparece em Partilhar | Confirmar o passo 3 ("Mostrar na folha de partilha" e "Páginas web do Safari") |
| Erro "não é permitido executar scripts" | Passo 1 |
| Erro "a entrada não é uma página web" | No passo 4, "Página web" tem de ser a Entrada do atalho |
| O fio diz "O que está copiado não veio do atalho" | Correr o atalho outra vez na página da peça. Outra cópia pelo meio apaga a do atalho |
| O fio diz "A página não tem os dados do produto" | A loja mudou a página; mandar o link para afinar |

O texto copiado só tem dados da página do produto: o link, o título, os dados estruturados e as meta tags. Não tem cookies nem nada da tua conta na loja.
