import { assertEquals } from '@std/assert';
import { type Deps, type Due, handle, payloadOf, type Subscription } from './handler.ts';

const token = 'a'.repeat(64);
const sub = (n: number): Subscription => ({
  endpoint: `https://push.example/${n}`,
  p256dh: 'p'.repeat(87),
  auth: 'a'.repeat(22),
});
const due: Due = {
  kind: 'eve',
  day: '2026-11-07',
  title: 'fio',
  body: 'Amanhã: t-shirt + calças.',
  url: '/planeador',
  subscriptions: [sub(1), sub(2)],
};

function deps(over: Partial<Deps> = {}): Deps & { dropped: string[]; sent: string[] } {
  const dropped: string[] = [];
  const sent: string[] = [];
  return {
    publicKey: 'BPUB',
    claim: () => Promise.resolve([due]),
    drop: (_t, _k, e) => {
      dropped.push(...e);
      return Promise.resolve();
    },
    send: (s, p) => {
      sent.push(`${s.endpoint} ${p}`);
      return Promise.resolve(201);
    },
    ...over,
    dropped,
    sent,
  };
}

const post = (body: unknown) =>
  new Request('https://x/reminders', { method: 'POST', body: JSON.stringify(body) });

Deno.test('GET devolve a chave pública, ou 503 sem chaves', async () => {
  const ok = await handle(new Request('https://x/reminders'), deps());
  assertEquals(await ok.json(), { publicKey: 'BPUB' });
  const none = await handle(new Request('https://x/reminders'), deps({ publicKey: null }));
  assertEquals(none.status, 503);
});

Deno.test('envia cada lembrete a todos os aparelhos', async () => {
  const d = deps();
  const res = await handle(post({ token }), d);
  assertEquals(await res.json(), { reminders: 1, sent: 2, failed: 0, gone: 0 });
  assertEquals(d.sent, [
    `https://push.example/1 ${payloadOf(due)}`,
    `https://push.example/2 ${payloadOf(due)}`,
  ]);
  assertEquals(JSON.parse(payloadOf(due)), {
    title: 'fio',
    body: 'Amanhã: t-shirt + calças.',
    url: '/planeador',
    tag: 'eve-2026-11-07',
  });
});

Deno.test('aparelhos desaparecidos são esquecidos; erros contam como falha', async () => {
  const d = deps({
    send: (s) =>
      s.endpoint.endsWith('1') ? Promise.resolve(410) : Promise.reject(new Error('rede')),
  });
  const res = await handle(post({ token }), d);
  assertEquals(await res.json(), { reminders: 1, sent: 0, failed: 1, gone: 1 });
  assertEquals(d.dropped, ['https://push.example/1']);
});

Deno.test('sem token válido não faz nada', async () => {
  assertEquals((await handle(post({}), deps())).status, 400);
  assertEquals((await handle(post({ token: 'curto' }), deps())).status, 400);
  const refused = await handle(post({ token }), deps({ claim: () => Promise.resolve(null) }));
  assertEquals(refused.status, 403);
});
