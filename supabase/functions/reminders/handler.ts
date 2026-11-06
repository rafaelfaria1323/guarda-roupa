// Lembretes por notificação (docs/features/lembretes.md).
//
// GET  devolve a chave pública VAPID (a app precisa dela para subscrever).
// POST { token } vem do pg_cron: pede à base os lembretes que chegaram à hora
//      (claim_due_reminders, só com o token do cron) e envia cada um a todos
//      os aparelhos do utilizador. A base marca-os como enviados antes de
//      sair, por isso um pedido repetido não envia nada de novo.

export interface Subscription {
  endpoint: string;
  p256dh: string;
  auth: string;
}

export interface Due {
  kind: 'wear_check' | 'eve';
  day: string;
  title: string;
  body: string;
  url: string;
  subscriptions: Subscription[] | null;
}

export interface Deps {
  /** `null` enquanto o workflow não criou as chaves. */
  publicKey: string | null;
  /** `null` se a base recusou o token. */
  claim: (token: string, apiKey: string | null) => Promise<Due[] | null>;
  /** Esquece os aparelhos que o serviço de push deu como desaparecidos. */
  drop: (token: string, apiKey: string | null, endpoints: string[]) => Promise<void>;
  /** Envia uma mensagem cifrada; devolve o estado HTTP do serviço de push. */
  send: (subscription: Subscription, payload: string) => Promise<number>;
}

const CORS = {
  'access-control-allow-origin': '*',
  'access-control-allow-headers': 'authorization, apikey, content-type, x-client-info',
  'access-control-allow-methods': 'GET, POST, OPTIONS',
};

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, 'content-type': 'application/json' },
  });
}

/** O que o service worker da app recebe (web/push_worker.js). */
export function payloadOf(due: Due): string {
  return JSON.stringify({
    title: due.title,
    body: due.body,
    url: due.url,
    tag: `${due.kind}-${due.day}`,
  });
}

export async function handle(req: Request, deps: Deps): Promise<Response> {
  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: CORS });
  if (req.method === 'GET') {
    return deps.publicKey == null
      ? json(503, { error: 'not_configured' })
      : json(200, { publicKey: deps.publicKey });
  }
  if (req.method !== 'POST') return json(405, { error: 'method' });

  let token: unknown;
  try {
    token = (await req.json())?.token;
  } catch {
    return json(400, { error: 'body' });
  }
  if (typeof token !== 'string' || token.length < 32 || token.length > 200) {
    return json(400, { error: 'token' });
  }
  if (deps.publicKey == null) return json(503, { error: 'not_configured' });
  const apiKey = req.headers.get('apikey');
  const due = await deps.claim(token, apiKey);
  if (due == null) return json(403, { error: 'forbidden' });

  let sent = 0;
  let failed = 0;
  const gone: string[] = [];
  const jobs = due.flatMap((d) =>
    (d.subscriptions ?? []).map(async (s) => {
      try {
        const status = await deps.send(s, payloadOf(d));
        if (status >= 200 && status < 300) sent++;
        else if (status === 404 || status === 410) gone.push(s.endpoint);
        else failed++;
      } catch {
        failed++;
      }
    })
  );
  await Promise.all(jobs);
  if (gone.length > 0) await deps.drop(token, apiKey, gone);
  return json(200, { reminders: due.length, sent, failed, gone: gone.length });
}
