// Edge Function `import-product` (docs/features/importacao-de-links.md).
import { handle, type Quota, type Recorded } from './handler.ts';

const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
// A chave pública que o cliente já envia (publishable); a do ambiente só
// como alternativa.
const envKey = Deno.env.get('SUPABASE_ANON_KEY') ?? '';

/** Chama uma função da base como o utilizador do token. */
async function rpc(
  name: string,
  authorization: string,
  apiKey: string | null,
  args: Record<string, unknown> = {},
): Promise<Response> {
  return await fetch(`${supabaseUrl}/rest/v1/rpc/${name}`, {
    method: 'POST',
    headers: {
      apikey: apiKey ?? envKey,
      authorization,
      'content-type': 'application/json',
    },
    body: JSON.stringify(args),
  });
}

/** A base valida o token, a allowlist e a quota (`claim_import_quota`). */
async function claimQuota(authorization: string, apiKey: string | null): Promise<Quota> {
  const res = await rpc('claim_import_quota', authorization, apiKey);
  if (res.status === 401 || res.status === 403) {
    await res.body?.cancel();
    return 'unauthorized';
  }
  if (!res.ok) {
    await res.body?.cancel();
    throw new Error(`claim_import_quota: ${res.status}`);
  }
  const value = await res.json();
  return value === 'ok' || value === 'forbidden' || value === 'rate_limited'
    ? value
    : 'unauthorized';
}

Deno.serve((req) =>
  handle(req, {
    claimQuota,
    record: async (authorization, apiKey, e) => {
      const res = await rpc('record_import', authorization, apiKey, {
        p_host: e.host,
        p_result: e.result,
        p_source: e.source ?? null,
        p_images: e.images,
      });
      if (!res.ok) {
        await res.body?.cancel();
        return null;
      }
      return await res.json() as Recorded;
    },
    imageAllowed: async (authorization, apiKey, url) => {
      const res = await rpc('import_image_allowed', authorization, apiKey, { p_url: url });
      if (!res.ok) {
        await res.body?.cancel();
        return false;
      }
      return (await res.json()) === true;
    },
  })
);
