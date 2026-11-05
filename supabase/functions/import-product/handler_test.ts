import { assertEquals } from '@std/assert';
import { type Deps, handle, type Quota, type Recorded } from './handler.ts';
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
