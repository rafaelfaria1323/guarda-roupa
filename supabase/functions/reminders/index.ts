// Edge Function `reminders` (docs/features/lembretes.md).
import webpush from 'web-push';
import { type Due, handle, type Subscription } from './handler.ts';

const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
const envKey = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
const publicKey = Deno.env.get('VAPID_PUBLIC_KEY') ?? null;
const privateKey = Deno.env.get('VAPID_PRIVATE_KEY') ?? null;
// Contacto para os serviços de push: o endereço da app.
const subject = Deno.env.get('VAPID_SUBJECT') ?? 'https://guarda-roupa-7z0.pages.dev';

/** Chama uma função da base como anónimo: o token do cron é a autorização. */
async function rpc(name: string, apiKey: string | null, args: unknown): Promise<Response> {
  const key = apiKey ?? envKey;
  return await fetch(`${supabaseUrl}/rest/v1/rpc/${name}`, {
    method: 'POST',
    headers: { apikey: key, 'content-type': 'application/json' },
    body: JSON.stringify(args),
  });
}

async function send(s: Subscription, payload: string): Promise<number> {
  const request = webpush.generateRequestDetails(
    { endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } },
    payload,
    {
      vapidDetails: { subject, publicKey: publicKey!, privateKey: privateKey! },
      // Um lembrete da noite já não serve no dia seguinte.
      TTL: 6 * 3600,
      urgency: 'normal',
    },
  );
  const res = await fetch(request.endpoint, {
    method: request.method,
    headers: request.headers,
    body: request.body,
    signal: AbortSignal.timeout(10_000),
  });
  await res.body?.cancel();
  return res.status;
}

Deno.serve((req) =>
  handle(req, {
    publicKey: publicKey != null && privateKey != null ? publicKey : null,
    claim: async (token, apiKey) => {
      const res = await rpc('claim_due_reminders', apiKey, { p_token: token });
      if (!res.ok) {
        await res.body?.cancel();
        return null;
      }
      return await res.json() as Due[];
    },
    drop: async (token, apiKey, endpoints) => {
      const res = await rpc('drop_push_subscriptions', apiKey, {
        p_token: token,
        p_endpoints: endpoints,
      });
      await res.body?.cancel();
    },
    send,
  })
);
