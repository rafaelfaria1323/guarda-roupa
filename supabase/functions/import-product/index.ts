// Edge Function `import-product` (docs/features/importacao-de-links.md).
import { handle, type Quota } from './handler.ts';

const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
// A chave pública que o cliente já envia (publishable); a do ambiente só
// como alternativa.
const envKey = Deno.env.get('SUPABASE_ANON_KEY') ?? '';

/** A base valida o token, a allowlist e a quota (`claim_import_quota`). */
async function claimQuota(authorization: string, apiKey: string | null): Promise<Quota> {
  const res = await fetch(`${supabaseUrl}/rest/v1/rpc/claim_import_quota`, {
    method: 'POST',
    headers: {
      apikey: apiKey ?? envKey,
      authorization,
      'content-type': 'application/json',
    },
    body: '{}',
  });
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

Deno.serve((req) => handle(req, { claimQuota }));
