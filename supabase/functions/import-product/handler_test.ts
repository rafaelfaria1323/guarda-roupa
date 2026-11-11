import { assertEquals } from '@std/assert';
import { type Deps, handle, type InboxResult, type Quota, type Recorded } from './handler.ts';
import { LIMITS } from './fetch_limited.ts';

const fixture = (name: string) =>
  Deno.readTextFileSync(new URL(`./fixtures/${name}`, import.meta.url));

type Route = (url: URL) => Response | Promise<Response>;

// Sem DNS nos testes: só as regras dos nomes (há um teste próprio).
const noDns = () => Promise.resolve(null);

function deps(route: Route, quota: Quota = 'ok', offered: string[] = []) {
  const log = {
    claims: 0,
    fetched: [] as string[],
    recorded: [] as { host: string; result: string; source?: string; images: string[] }[],
  };
  const granted = new Set(offered);
  const d: Deps = {
    claimQuota: () => {
      log.claims++;
      return Promise.resolve(quota);
    },
    record: (_a, _k, e) => {
      log.recorded.push(e);
      e.images.forEach((i) => granted.add(i));
      const r: Recorded = { status: 'testing', ok_count: 1, fail_count: 0 };
      return Promise.resolve(r);
    },
    imageAllowed: (_a, _k, url) => Promise.resolve(granted.has(url)),
    resolve: noDns,
    fetchFn: async (url, init) => {
      assertEquals(init.redirect, 'manual');
      log.fetched.push(url.href);
      return await route(url);
    },
  };
  return { d, log };
}

const post = (body: unknown, auth = 'Bearer t') =>
  new Request('https://fn/import-product', {
    method: 'POST',
    headers: { authorization: auth, 'content-type': 'application/json' },
    body: JSON.stringify(body),
  });

const html = (text: string, status = 200) =>
  new Response(text, {
    status,
    headers: { 'content-type': 'text/html; charset=utf-8' },
  });

Deno.test('produto: pré-visualização e perfil do site atualizado', async () => {
  const { d, log } = deps(() => html(fixture('product_group.html')));
  const res = await handle(
    post({ url: 'https://www.zara.com/pt/pt/c-p1.html' }),
    d,
  );
  const body = await res.json();
  assertEquals(body.result, 'ok');
  assertEquals(body.store, { id: 'www.zara.com', name: 'Zara', status: 'testing', okCount: 1 });
  assertEquals(body.product.images.length, 2);
  assertEquals(log.claims, 1);
  assertEquals(log.recorded.length, 1);
  assertEquals(log.recorded[0].result, 'ok');
  assertEquals(log.recorded[0].source, 'json-ld');
  // As imagens das variantes também ficam autorizadas.
  assertEquals(log.recorded[0].images.includes('https://static.zara.net/azul.jpg'), true);
});

Deno.test('qualquer site: nome a partir do domínio', async () => {
  const { d } = deps(() => html(fixture('microdata.html')));
  const body = await (await handle(post({ url: 'https://www.loja-nova.pt/p/1' }), d)).json();
  assertEquals([body.result, body.store.name], ['ok', 'loja-nova.pt']);
});

Deno.test('link inválido ou interno: recusado sem pedir nem gastar quota', async () => {
  const { d, log } = deps(() => html('x'));
  for (
    const [url, result] of [
      ['http://www.zara.com/p', 'invalid_url'],
      ['https://169.254.169.254/latest', 'not_public'],
      ['https://localhost/p', 'not_public'],
    ]
  ) {
    const body = await (await handle(post({ url }), d)).json();
    assertEquals(body.result, result, url);
  }
  assertEquals([log.claims, log.fetched.length, log.recorded.length], [0, 0, 0]);
});

Deno.test('sem token, fora da allowlist ou sem quota', async () => {
  const url = 'https://www.zara.com/p';
  assertEquals(
    (await handle(post({ url }, ''), deps(() => html('')).d)).status,
    401,
  );
  assertEquals(
    (await handle(post({ url }), deps(() => html(''), 'forbidden').d)).status,
    403,
  );
  const limited = await handle(
    post({ url }),
    deps(() => html(''), 'rate_limited').d,
  );
  assertEquals([limited.status, (await limited.json()).result], [
    429,
    'rate_limited',
  ]);
});

Deno.test('redirecionamentos: para sites públicos segue, para dentro para', async () => {
  const inside = deps((url) =>
    url.pathname === '/a'
      ? new Response(null, { status: 301, headers: { location: '/b' } })
      : html(fixture('product_graph.html'))
  );
  const ok = await (await handle(post({ url: 'https://www.zara.com/a' }), inside.d))
    .json();
  assertEquals([ok.result, ok.url], ['ok', 'https://www.zara.com/b']);

  const other = deps((url) =>
    url.hostname === 'www.zara.com'
      ? new Response(null, { status: 302, headers: { location: 'https://zara.com/b' } })
      : html(fixture('product_graph.html'))
  );
  const moved = await (await handle(post({ url: 'https://www.zara.com/a' }), other.d)).json();
  assertEquals([moved.result, moved.store.id], ['ok', 'zara.com']);

  for (
    const location of [
      'https://169.254.169.254/',
      'https://intranet.local/x',
      'http://www.zara.com/b',
    ]
  ) {
    const out = deps(() => new Response(null, { status: 302, headers: { location } }));
    const body = await (await handle(post({ url: 'https://www.zara.com/a' }), out.d))
      .json();
    assertEquals([body.result, body.reason], [
      'fetch_failed',
      'redirect_not_allowed',
    ], location);
    assertEquals(out.log.fetched, ['https://www.zara.com/a']);
  }

  const loop = deps(() => new Response(null, { status: 302, headers: { location: '/a' } }));
  const body = await (await handle(post({ url: 'https://www.zara.com/a' }), loop.d))
    .json();
  assertEquals(body.reason, 'too_many_redirects');
  assertEquals(loop.log.fetched.length, LIMITS.maxRedirects + 1);
});

Deno.test('erros reais ditos como tal', async () => {
  const cases: [Response, string][] = [
    [html('', 403), 'blocked'],
    [html('', 404), 'not_found'],
    [html('', 500), 'http_error'],
    [
      new Response('{}', { headers: { 'content-type': 'application/json' } }),
      'not_html',
    ],
    [html('x'.repeat(LIMITS.maxPageBytes + 1)), 'too_large'],
  ];
  for (const [res, reason] of cases) {
    const body = await (await handle(
      post({ url: 'https://www.zara.com/p' }),
      deps(() => res).d,
    )).json();
    assertEquals([body.result, body.reason], ['fetch_failed', reason]);
  }
  const none = await (await handle(
    post({ url: 'https://www.zara.com/p' }),
    deps(() => html(fixture('none.html'))).d,
  )).json();
  assertEquals(none.result, 'no_metadata');
});

Deno.test('imagem: só as oferecidas numa pré-visualização', async () => {
  const png = new Uint8Array([137, 80, 78, 71]);
  const offered = 'https://cdn.loja-nova.pt/a.png';
  const { d, log } = deps(
    () => new Response(png, { headers: { 'content-type': 'image/png' } }),
    'ok',
    [offered],
  );
  const res = await handle(post({ image: offered }), d);
  assertEquals(res.headers.get('content-type'), 'image/png');
  assertEquals(new Uint8Array(await res.arrayBuffer()), png);

  const other = await handle(post({ image: 'https://example.com/a.png' }), d);
  assertEquals([other.status, (await other.json()).result], [403, 'image_not_offered']);
  assertEquals(log.fetched, [offered], 'a não oferecida nem se pede');

  const internal = await (await handle(post({ image: 'https://10.0.0.1/a.png' }), d)).json();
  assertEquals(internal.result, 'not_public');

  const svgUrl = 'https://cdn.loja-nova.pt/a.svg';
  const svg = deps(
    () => new Response('<svg/>', { headers: { 'content-type': 'image/svg+xml' } }),
    'ok',
    [svgUrl],
  );
  const notImage = await (await handle(post({ image: svgUrl }), svg.d)).json();
  assertEquals(notImage.reason, 'not_image');
});

Deno.test('falhas também atualizam o perfil; sem perfil a importação segue', async () => {
  const failed = deps(() => html('', 403));
  const body = await (await handle(post({ url: 'https://loja.example/p' }), failed.d)).json();
  assertEquals([body.result, body.reason], ['fetch_failed', 'blocked']);
  assertEquals(failed.log.recorded.map((r) => r.result), ['fetch_failed']);

  const broken = deps(() => html(fixture('og_only.html')));
  broken.d.record = () => Promise.reject(new Error('base em baixo'));
  const ok = await (await handle(post({ url: 'https://loja.example/p' }), broken.d)).json();
  assertEquals([ok.result, ok.store.status], ['ok', 'new']);
});

Deno.test('desafio anti-bot (Akamai): bloqueado, não "sem dados"', async () => {
  const { d, log } = deps(() => html(fixture('bot_challenge.html')));
  const res = await handle(
    post({ url: 'https://www.massimodutti.com/pt/camisa-l1' }),
    d,
  );
  const body = await res.json();
  assertEquals(body.result, 'fetch_failed');
  assertEquals(body.reason, 'blocked');
  assertEquals(body.store.name, 'Massimo Dutti');
  assertEquals(log.recorded.map((r) => r.result), ['fetch_failed']);
  assertEquals(log.fetched.length, 1);
});

Deno.test('página com produto e script anti-bot continua a dar o produto', async () => {
  const page = fixture('product_group.html').replace(
    '</head>',
    '<script src="https://js.captcha-delivery.com/tags.js"></script></head>',
  );
  const { d } = deps(() => html(page));
  const res = await handle(post({ url: 'https://www.zara.com/pt/pt/c-p1.html' }), d);
  assertEquals((await res.json()).result, 'ok');
});

// O que o atalho do iPhone copia de uma página da Zara (forma real, dados
// sintéticos).
const sharedZara = {
  title: 'CASACO EM PELE - Preto | ZARA Portugal',
  ld: [
    JSON.stringify({
      '@context': 'https://schema.org/',
      '@type': 'ProductGroup',
      name: 'CASACO EM PELE',
      brand: { '@type': 'Brand', name: 'ZARA' },
      description: 'Casaco em pele. Gola com lapelas largas. </script><b>x</b>',
      image: ['https://static.zara.net/assets/public/a/05479600800-p.jpg'],
      hasVariant: [
        { '@type': 'Product', color: 'Preto', size: 'M', sku: '1-M' },
        { '@type': 'Product', color: 'Preto', size: 'L', sku: '1-L' },
      ],
    }),
  ],
  meta: [
    ['og:title', 'CASACO EM PELE'],
    ['og:image', 'https://static.zara.net/assets/public/a/05479600800-p.jpg?w=560'],
  ],
};

Deno.test('página partilhada pelo atalho: produto sem pedir a página à loja', async () => {
  const { d, log } = deps(() => {
    throw new Error('não devia pedir nada à loja');
  });
  const res = await handle(
    post({ url: 'https://www.zara.com/pt/pt/casaco-p05479600.html', page: sharedZara }),
    d,
  );
  const body = await res.json();
  assertEquals(body.result, 'ok');
  assertEquals(body.via, 'shared');
  assertEquals(body.product.name, 'CASACO EM PELE');
  assertEquals(body.product.brand, 'ZARA');
  // O `</script>` do texto não fecha o bloco antes do tempo.
  assertEquals(
    body.product.description.startsWith('Casaco em pele. Gola com lapelas largas.'),
    true,
  );
  assertEquals(body.store.name, 'Zara');
  assertEquals(log.fetched, []);
  assertEquals(log.claims, 1);
  assertEquals(log.recorded.map((r) => r.result), ['shared']);
  assertEquals(
    log.recorded[0].images.includes('https://static.zara.net/assets/public/a/05479600800-p.jpg'),
    true,
  );
});

Deno.test('página partilhada: a imagem oferecida pode ser copiada', async () => {
  const img = 'https://static.zara.net/assets/public/a/05479600800-p.jpg';
  const { d, log } = deps((url) =>
    url.hostname === 'static.zara.net'
      ? new Response(new Uint8Array([1, 2, 3]), { headers: { 'content-type': 'image/webp' } })
      : html('não')
  );
  await handle(
    post({ url: 'https://www.zara.com/pt/pt/casaco-p05479600.html', page: sharedZara }),
    d,
  );
  const res = await handle(post({ image: img }), d);
  assertEquals(res.status, 200);
  assertEquals(log.fetched, [img]);
});

Deno.test('página partilhada mal formada: recusada sem gastar quota', async () => {
  const { d, log } = deps(() => html(''));
  for (
    const page of [
      'texto',
      { ld: 'não é lista' },
      { ld: [1] },
      { meta: [['og:title']] },
      { ld: Array(11).fill('{}') },
      { ld: ['x'.repeat(200_001)] },
    ]
  ) {
    const res = await handle(post({ url: 'https://www.zara.com/pt/pt/a.html', page }), d);
    assertEquals(res.status, 400);
  }
  const res = await handle(post({ image: 'https://a.example/x.jpg', page: { ld: [] } }), d);
  assertEquals(res.status, 400);
  assertEquals(log.claims, 0);
});

Deno.test('página partilhada sem produto: sem dados', async () => {
  const { d } = deps(() => html(''));
  const res = await handle(
    post({ url: 'https://www.zara.com/pt/pt/a.html', page: { title: 'ZARA', ld: [], meta: [] } }),
    d,
  );
  assertEquals((await res.json()).result, 'no_metadata');
});

Deno.test('página partilhada com link interno: recusada', async () => {
  const { d, log } = deps(() => html(''));
  const res = await handle(
    post({ url: 'https://localhost/a', page: sharedZara }),
    d,
  );
  assertEquals((await res.json()).result, 'not_public');
  assertEquals(log.claims, 0);
});

// Atalho que envia logo para o fio: chave no cabeçalho, sem sessão.
function inboxDeps(result: InboxResult | 'throw' = 'ok') {
  const { d, log } = deps(() => {
    throw new Error('a loja não pode ser pedida');
  });
  const sent: {
    key: string;
    apiKey: string | null;
    url: string;
    preview: unknown;
    images: string[];
  }[] = [];
  d.submitInbox = (key, apiKey, e) => {
    if (result === 'throw') return Promise.reject(new Error('rede'));
    sent.push({ key, apiKey, ...e });
    return Promise.resolve(result);
  };
  return { d, log, sent };
}

const toInbox = (body: unknown, key = 'fio_chave_de_teste_1234567890', query = '?apikey=pub') =>
  new Request(`https://fn/import-product${query}`, {
    method: 'POST',
    headers: { 'x-fio-key': key, 'content-type': 'text/plain' },
    body: typeof body === 'string' ? body : JSON.stringify(body),
  });

const zaraShortcut = {
  fio: 1,
  url: 'https://www.zara.com/pt/pt/casaco-p05479600.html',
  ...sharedZara,
};

Deno.test('atalho direto: fica na caixa, sem pedir a loja nem quota com sessão', async () => {
  const { d, log, sent } = inboxDeps();
  const res = await handle(toInbox(zaraShortcut), d);
  assertEquals(res.status, 200);
  assertEquals((await res.text()).startsWith('Enviada para o fio: '), true);
  assertEquals(log.fetched, []);
  assertEquals(log.claims, 0);
  assertEquals(sent.length, 1);
  assertEquals(sent[0].key, 'fio_chave_de_teste_1234567890');
  assertEquals(sent[0].apiKey, 'pub');
  assertEquals(sent[0].url, zaraShortcut.url);
  const preview = sent[0].preview as Record<string, unknown>;
  assertEquals(preview.result, 'ok');
  assertEquals(preview.via, 'shared');
  assertEquals((preview.store as Record<string, unknown>).name, 'Zara');
  assertEquals(sent[0].images.length > 0, true);
});

Deno.test('atalho direto: as fotos da galeria do mesmo produto vêm para escolher', async () => {
  const a1 = 'https://static.zara.net/assets/public/b/05479600800-a1.jpg?w=1024';
  const e1 = 'https://static.zara.net/assets/public/c/05479600800-e1.jpg?w=1024';
  const gallery = [a1, 'https://static.zara.net/assets/public/d/01234500800-p.jpg', e1];
  const { d, sent } = inboxDeps();
  const res = await handle(toInbox({ ...zaraShortcut, gallery }), d);
  assertEquals(res.status, 200);
  const product = (sent[0].preview as { product: { images: string[] } }).product;
  assertEquals(product.images.includes(a1) && product.images.includes(e1), true);
  assertEquals(product.images.some((i) => i.includes('01234500800')), false);
  // As fotos da galeria ficam autorizadas para a app as copiar.
  assertEquals(sent[0].images.includes(a1) && sent[0].images.includes(e1), true);
});

Deno.test('atalho direto: apikey no cabeçalho vale mais que no link', async () => {
  const { d, sent } = inboxDeps();
  const req = toInbox(zaraShortcut);
  req.headers.set('apikey', 'hdr');
  await handle(req, d);
  assertEquals(sent[0].apiKey, 'hdr');
});

Deno.test('atalho direto: corpo errado ou sem produto', async () => {
  const { d, sent } = inboxDeps();
  assertEquals((await handle(toInbox('não é json'), d)).status, 400);
  assertEquals((await handle(toInbox({ ...zaraShortcut, fio: 2 }), d)).status, 400);
  assertEquals((await handle(toInbox({ fio: 1, ld: [], meta: [] }), d)).status, 400);
  assertEquals(
    (await handle(toInbox({ fio: 1, url: zaraShortcut.url, ld: 'x', meta: [] }), d)).status,
    400,
  );
  assertEquals(
    (await handle(toInbox({ ...zaraShortcut, url: 'https://localhost/a' }), d)).status,
    400,
  );
  const empty = await handle(
    toInbox({ fio: 1, url: zaraShortcut.url, title: 'ZARA', ld: [], meta: [] }),
    d,
  );
  assertEquals(empty.status, 422);
  assertEquals(sent.length, 0);
});

Deno.test('atalho direto: cada resposta da base tem a sua mensagem', async () => {
  const cases: [InboxResult | 'throw', number][] = [
    ['invalid_key', 401],
    ['forbidden', 403],
    ['rate_limited', 429],
    ['full', 409],
    ['throw', 503],
  ];
  for (const [result, status] of cases) {
    const { d } = inboxDeps(result);
    const res = await handle(toInbox(zaraShortcut), d);
    assertEquals(res.status, status, result);
    assertEquals(res.headers.get('content-type'), 'text/plain; charset=utf-8');
    assertEquals((await res.text()).length > 0, true);
  }
});

// Pinterest e Instagram: inspirações, nunca pedidas ao site.
const pinShortcut = {
  fio: 1,
  url: 'https://pt.pinterest.com/pin/24558760455894205/',
  title: 'Pin em Estilo',
  ld: [],
  meta: [
    ['og:site_name', 'Pinterest'],
    ['og:image', 'https://i.pinimg.com/736x/b8/58/a4/x.jpg'],
    ['og:url', 'https://www.pinterest.com/pin/minimalist-fashion--24558760455894205/'],
    ['og:title', 'Minimalist Fashion Inspiration | Pinterest'],
    ['og:description', 'Blazer,   calças largas e sabrinas.'],
  ],
};

Deno.test('atalho num Pin: inspiração na caixa, sem pedir nada ao Pinterest', async () => {
  const { d, log, sent } = inboxDeps();
  const res = await handle(toInbox(pinShortcut), d);
  assertEquals(res.status, 200);
  assertEquals(
    await res.text(),
    'Inspiração enviada para o fio: Minimalist Fashion Inspiration. A imagem do Pin não veio.',
  );
  assertEquals(log.fetched, []);
  assertEquals(sent.length, 1);
  assertEquals(sent[0].images, []);
  assertEquals(sent[0].url, 'https://www.pinterest.com/pin/minimalist-fashion--24558760455894205/');
  assertEquals(sent[0].preview, {
    result: 'ok',
    kind: 'inspiration',
    site: 'Pinterest',
    url: 'https://www.pinterest.com/pin/minimalist-fashion--24558760455894205/',
    inspiration: {
      title: 'Minimalist Fashion Inspiration',
      description: 'Blazer, calças largas e sabrinas.',
    },
    via: 'shared',
  });
});

Deno.test('atalho num Pin com a imagem lida no Safari: vai na caixa', async () => {
  // Um JPEG mínimo (só o cabeçalho conta para a validação).
  const jpeg = btoa(String.fromCharCode(0xff, 0xd8, 0xff, 0xe0) + 'x'.repeat(200));
  const { d, log, sent } = inboxDeps();
  const res = await handle(toInbox({ ...pinShortcut, image: jpeg }), d);
  assertEquals(res.status, 200);
  assertEquals(
    await res.text(),
    'Inspiração enviada para o fio, com a imagem: Minimalist Fashion Inspiration.',
  );
  assertEquals(log.fetched, []);
  assertEquals(sent[0].images, []);
  const found = (sent[0].preview as { inspiration: Record<string, unknown> }).inspiration;
  assertEquals(found.image, jpeg);

  // O que não é um JPEG em base64, ou é grande demais, fica de fora.
  for (
    const bad of [
      btoa('GIF89a' + 'x'.repeat(200)),
      'data:image/jpeg;base64,' + jpeg,
      jpeg.slice(0, 40),
      btoa(String.fromCharCode(0xff, 0xd8, 0xff) + 'x'.repeat(700_000)),
      42,
    ]
  ) {
    const { d, sent } = inboxDeps();
    const res = await handle(
      toInbox({ ...pinShortcut, image: bad, imageWhy: 'sem imagem: 3 img, 0 pinimg<>' }),
      d,
    );
    assertEquals(res.status, 200);
    assertEquals(
      await res.text(),
      'Inspiração enviada para o fio: Minimalist Fashion Inspiration. ' +
        'A imagem do Pin não veio (sem imagem: 3 img, 0 pinimg).',
    );
    const found = (sent[0].preview as { inspiration: Record<string, unknown> }).inspiration;
    assertEquals('image' in found, false);
  }
});

Deno.test('atalho num Pin sem meta tags: fica o link, com o nome do site', async () => {
  const { d, sent } = inboxDeps();
  const res = await handle(
    toInbox({ fio: 1, url: 'https://pin.it/abc', title: 'Pinterest', ld: [], meta: [] }),
    d,
  );
  assertEquals(
    await res.text(),
    'Inspiração enviada para o fio: Pinterest. A imagem do Pin não veio.',
  );
  const preview = sent[0].preview as Record<string, unknown>;
  assertEquals(preview.url, 'https://pin.it/abc');
  assertEquals(preview.inspiration, { title: undefined, description: undefined });
});

Deno.test('atalho num Pin: og:url de outro site não substitui o link', async () => {
  const { d, sent } = inboxDeps();
  await handle(
    toInbox({
      ...pinShortcut,
      meta: [['og:url', 'https://outro.example/pin'], ['og:title', 'Look']],
    }),
    d,
  );
  assertEquals(sent[0].url, pinShortcut.url);
});

Deno.test('link do Pinterest ou Instagram colado na app: não se lê nem gasta quota', async () => {
  for (const url of ['https://www.pinterest.com/pin/1/', 'https://www.instagram.com/p/x/']) {
    const { d, log } = deps(() => html('não pode ser pedido'));
    const body = await (await handle(post({ url }), d)).json();
    assertEquals(body.result, 'inspiration_site');
    assertEquals(log.fetched, []);
    assertEquals(log.claims, 0);
  }
});
