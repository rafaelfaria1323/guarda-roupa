import { assertEquals } from '@std/assert';
import { type Deps, handle, pickOf } from './handler.ts';

const garments = [
  { id: 'p1', category: 't_shirt', name: 'Branca', colors: ['white'], wears_30d: 2 },
  { id: 'p2', category: 'jeans', colors: ['denim'], last_worn_days: 3, secret: 'x' },
  { id: 'p3', category: 'sneakers' },
];

function deps(over: Partial<Deps> = {}): Deps & { prompts: string[] } {
  const prompts: string[] = [];
  return {
    prompts,
    configured: true,
    claimQuota: () => Promise.resolve('ok'),
    generate: (prompt) => {
      prompts.push(prompt);
      return Promise.resolve({
        text: JSON.stringify({
          name: 'Básico   de sábado',
          items: [
            { id: 'p1', role: 'main_top' },
            { id: 'p2', role: 'bottom' },
            { id: 'p9', role: 'footwear' },
            { id: 'p1', role: 'main_top' },
            { id: 'p3', role: 'sapatos' },
          ],
          why: 'Simples e confortável.',
        }),
      });
    },
    ...over,
  };
}

function post(body: unknown, auth = 'Bearer t'): Request {
  return new Request('http://x/', {
    method: 'POST',
    headers: { authorization: auth, 'content-type': 'application/json' },
    body: JSON.stringify(body),
  });
}

Deno.test('só peças mandadas, sem repetir, com papéis conhecidos', async () => {
  const d = deps();
  const res = await handle(
    post({ garments, occasion: 'casual', weather: { feels_like_c: 99, rain: true }, ask: 'x' }),
    d,
  );
  assertEquals(res.status, 200);
  assertEquals(await res.json(), {
    name: 'Básico de sábado',
    items: [{ id: 'p1', role: 'main_top' }, { id: 'p2', role: 'bottom' }],
    why: 'Simples e confortável.',
  });
  const brief = JSON.parse(d.prompts[0].slice(d.prompts[0].indexOf('{')));
  assertEquals(brief.weather, { feels_like_c: 55, rain: true, wind_kmh: 0, sunny: false });
  assertEquals(brief.wardrobe[1], {
    id: 'p2',
    category: 'jeans',
    colors: ['denim'],
    wears_30d: 0,
    last_worn_days: 3,
  });
});

Deno.test('inspirações e look alvo seguem só como etiquetas', async () => {
  const d = deps();
  const insp = { title: 'Linho', palette: ['white', 'beige'], image: 'x', url: 'https://a.b' };
  const res = await handle(
    post({
      garments,
      inspirations: Array.from({ length: 25 }, () => insp),
      target: { title: 'Noite', formality: 'dressy', notes: 'segredo' },
    }),
    d,
  );
  assertEquals(res.status, 200);
  const brief = JSON.parse(d.prompts[0].slice(d.prompts[0].indexOf('{')));
  assertEquals(brief.inspirations.length, 20);
  assertEquals(brief.inspirations[0], {
    title: 'Linho',
    palette: ['white', 'beige'],
    formality: null,
    patterns: [],
    textures: [],
    occasions: [],
    proportions: [],
  });
  assertEquals(brief.target.title, 'Noite');
  assertEquals(brief.target.formality, 'dressy');
  assertEquals(brief.target.notes, undefined);
  assertEquals(d.prompts[0].includes('segredo'), false);
});

Deno.test('pedidos inválidos não gastam quota', async () => {
  let claims = 0;
  const d = deps({
    claimQuota: () => {
      claims++;
      return Promise.resolve('ok');
    },
  });
  for (
    const body of [
      {},
      { garments: [garments[0]] },
      { garments: [garments[0], { ...garments[1], id: 'p1' }] },
      { garments: [garments[0], { ...garments[1], id: 'uuid-1234' }] },
      { garments: [garments[0], { id: 'p2' }] },
    ]
  ) {
    assertEquals((await handle(post(body), d)).status, 400);
  }
  assertEquals(claims, 0);
  assertEquals((await handle(post({ garments }, ''), d)).status, 401);
  assertEquals((await handle(post({ garments }), deps({ configured: false }))).status, 503);
});

Deno.test('quota e respostas estragadas', async () => {
  const limited = deps({ claimQuota: () => Promise.resolve('rate_limited') });
  const res = await handle(post({ garments }), limited);
  assertEquals([res.status, (await res.json()).error], [429, 'rate_limited']);
  assertEquals(limited.prompts.length, 0);
  const busy = deps({ generate: () => Promise.resolve({ status: 429 }) });
  assertEquals((await (await handle(post({ garments }), busy)).json()).error, 'busy');
  const empty = deps({ generate: () => Promise.resolve({ text: '{"items":[]}' }) });
  assertEquals((await handle(post({ garments }), empty)).status, 502);
});

Deno.test('pickOf', () => {
  assertEquals(pickOf(null, new Set()), null);
  assertEquals(
    pickOf({ items: [{ id: 'p1', role: 'one_piece' }] }, new Set(['p1'])),
    { name: null, items: [{ id: 'p1', role: 'one_piece' }], why: null },
  );
});

Deno.test('compras: limpa o pedido e só devolve ideias com marca', async () => {
  const d = deps({
    generate: (prompt) => {
      d.prompts.push(prompt);
      return Promise.resolve({
        text: JSON.stringify({
          ideas: [
            {
              category: 'sneakers',
              color: 'black',
              title: '  Ténis pretos   em pele ',
              why: 'Vão com a ganga.',
              search: 'ténis pretos pele',
              brands: [
                { name: 'COS', tier: 'same' },
                { name: 'COS', tier: 'same' },
                { name: 'Primark', tier: 'cheaper' },
                { name: 'X', tier: 'luxo' },
              ],
            },
            { category: 'nave', title: 'x', search: 'x', brands: [{ name: 'A', tier: 'same' }] },
            { category: 'jeans', title: 'Calças', search: 'calças', brands: [] },
          ],
        }),
      });
    },
  });
  const res = await handle(
    post({
      kind: 'shopping',
      garments: [
        { category: 'sneakers', colors: ['white'], brand: 'Uniqlo', notes: 'segredo' },
        { category: 'jeans', colors: ['denim'], brand: 'Uniqlo' },
      ],
      inspirations: [{ title: 'Preto e branco', palette: ['black'], formality: 'dressy' }],
      gaps: [{ reason: 'onlyLight', group: 'footwear', color: 'black' }, { reason: 'hack' }],
      budget_eur: 79.6,
      dismissed: ['idea:coat:navy'],
    }),
    d,
  );
  assertEquals(res.status, 200);
  assertEquals(await res.json(), {
    ideas: [{
      category: 'sneakers',
      color: 'black',
      title: 'Ténis pretos em pele',
      why: 'Vão com a ganga.',
      search: 'ténis pretos pele',
      brands: [{ name: 'COS', tier: 'same' }, { name: 'Primark', tier: 'cheaper' }],
    }],
  });
  const sent = d.prompts[0];
  assertEquals(sent.includes('segredo'), false);
  assertEquals(sent.includes('"brands_owned":["Uniqlo"]'), true);
  assertEquals(sent.includes('"budget_eur":80'), true);
  assertEquals(sent.includes('hack'), false);
});

Deno.test('compras: peça desconhecida não gasta quota', async () => {
  let claims = 0;
  const d = deps({
    claimQuota: () => {
      claims++;
      return Promise.resolve('ok');
    },
  });
  const res = await handle(post({ kind: 'shopping', garments: [{ category: 'nave' }] }), d);
  assertEquals([res.status, claims], [400, 0]);
});
