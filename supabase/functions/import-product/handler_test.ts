import { assertEquals } from '@std/assert';
import { type Deps, handle, type Quota } from './handler.ts';
import { LIMITS } from './fetch_limited.ts';

const fixture = (name: string) =>
  Deno.readTextFileSync(new URL(`./fixtures/${name}`, import.meta.url));

type Route = (url: URL) => Response | Promise<Response>;

function deps(route: Route, quota: Quota = 'ok') {
  const log = { claims: 0, fetched: [] as string[] };
  const d: Deps = {
    claimQuota: () => {
      log.claims++;
      return Promise.resolve(quota);
    },
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

Deno.test('produto: pré-visualização, só imagens copiáveis', async () => {
  const { d, log } = deps(() => html(fixture('product_group.html')));
  const res = await handle(
    post({ url: 'https://www.zara.com/pt/pt/c-p1.html' }),
    d,
  );
  const body = await res.json();
  assertEquals(body.result, 'ok');
  assertEquals(body.store, { id: 'zara', name: 'Zara', status: 'poc' });
  assertEquals(body.product.images, ['https://static.zara.net/a.jpg']);
  assertEquals(body.product.otherImages, 1);
  assertEquals(log.claims, 1);
});

Deno.test('outra loja ou link inválido: recusado sem pedir nem gastar quota', async () => {
  const { d, log } = deps(() => html('x'));
  for (const url of ['https://www.mango.com/p', 'http://www.zara.com/p']) {
    const body = await (await handle(post({ url }), d)).json();
    assertEquals(
      ['unsupported_store', 'invalid_url'].includes(body.result),
      true,
    );
  }
  assertEquals([log.claims, log.fetched.length], [0, 0]);
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

Deno.test('redirecionamentos: dentro da loja segue, para fora para', async () => {
  const inside = deps((url) =>
    url.pathname === '/a'
      ? new Response(null, { status: 301, headers: { location: '/b' } })
      : html(fixture('product_graph.html'))
  );
  const ok = await (await handle(post({ url: 'https://www.zara.com/a' }), inside.d))
    .json();
  assertEquals([ok.result, ok.url], ['ok', 'https://www.zara.com/b']);

  for (
    const location of [
      'https://169.254.169.254/',
      'https://www.bershka.com/x',
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

Deno.test('imagem: copia de um domínio de imagens da loja, mais nenhum', async () => {
  const png = new Uint8Array([137, 80, 78, 71]);
  const { d } = deps(() => new Response(png, { headers: { 'content-type': 'image/png' } }));
  const res = await handle(post({ image: 'https://static.zara.net/a.png' }), d);
  assertEquals(res.headers.get('content-type'), 'image/png');
  assertEquals(new Uint8Array(await res.arrayBuffer()), png);

  const other = await (await handle(post({ image: 'https://example.com/a.png' }), d))
    .json();
  assertEquals(other.result, 'unsupported_store');
  const svg = deps(() => new Response('<svg/>', { headers: { 'content-type': 'image/svg+xml' } }));
  const notImage = await (await handle(
    post({ image: 'https://static.zara.net/a.svg' }),
    svg.d,
  )).json();
  assertEquals(notImage.reason, 'not_image');
});
