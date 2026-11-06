import { assertEquals } from '@std/assert';
import { type Deps, garmentOf, handle, labelOf } from './handler.ts';

const image = 'A'.repeat(200);

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
          category: 'shirt',
          name: '  Camisa   às riscas ',
          colors: [{ color: 'white', share: 62 }, { color: 'navy', share: 40 }],
          pattern: 'stripes',
          texture: 'shiny',
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

Deno.test('peça: só valores conhecidos e cores que somam no máximo 100', async () => {
  const d = deps();
  const res = await handle(post({ kind: 'garment', image }), d);
  assertEquals(res.status, 200);
  assertEquals(await res.json(), {
    category: 'shirt',
    name: 'Camisa às riscas',
    colors: [{ color: 'white', share: 60 }, { color: 'navy', share: 40 }],
    pattern: 'stripes',
    texture: null,
    warmth: null,
    formality: null,
  });
  assertEquals(d.prompts.length, 1);
});

Deno.test('sem chave, sem sessão, fora da allowlist ou sem quota', async () => {
  assertEquals(
    (await handle(post({ kind: 'garment', image }), deps({ configured: false }))).status,
    503,
  );
  assertEquals((await handle(post({ kind: 'garment', image }, ''), deps())).status, 401);
  const forbidden = deps({ claimQuota: () => Promise.resolve('forbidden') });
  assertEquals((await handle(post({ kind: 'garment', image }), forbidden)).status, 403);
  assertEquals(forbidden.prompts.length, 0);
  const limited = deps({ claimQuota: () => Promise.resolve('rate_limited') });
  const res = await handle(post({ kind: 'label', image }), limited);
  assertEquals([res.status, (await res.json()).error], [429, 'rate_limited']);
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
      { kind: 'outfit', image },
      { kind: 'garment', image: 'curta' },
      { kind: 'garment', image: 'A'.repeat(150) + '!' },
      { kind: 'garment', image, mime: 'image/heic' },
    ]
  ) {
    assertEquals((await handle(post(body), d)).status, 400);
  }
  assertEquals(claims, 0);
});

Deno.test('quota do Gemini esgotada e resposta estragada', async () => {
  const busy = deps({ generate: () => Promise.resolve({ status: 429 }) });
  const res = await handle(post({ kind: 'garment', image }), busy);
  assertEquals([res.status, (await res.json()).error], [429, 'busy']);
  const broken = deps({ generate: () => Promise.resolve({ text: 'não é json' }) });
  assertEquals((await handle(post({ kind: 'garment', image }), broken)).status, 502);
});

Deno.test('etiqueta', () => {
  assertEquals(
    labelOf({ wash: 'machine_40', tumble_dry: false, material: '100% algodão', care: '' }),
    { wash: 'machine_40', tumble_dry: false, material: '100% algodão', care: null },
  );
  assertEquals(labelOf(null), { wash: null, tumble_dry: null, material: null, care: null });
});

Deno.test('cores: no máximo 3, sem repetir', () => {
  const g = garmentOf({
    colors: [
      { color: 'red', share: 50 },
      { color: 'red', share: 10 },
      { color: 'rosa', share: 10 },
      { color: 'blue', share: 30 },
      { color: 'black', share: 30 },
      { color: 'white', share: 5 },
    ],
  });
  assertEquals(g.colors, [
    { color: 'red', share: 50 },
    { color: 'blue', share: 30 },
    { color: 'black', share: 20 },
  ]);
});
