// Partilhado pelas funções que usam o Gemini (docs/features/ia-gemini.md).

export type Quota = 'ok' | 'forbidden' | 'rate_limited' | 'unauthorized';

/** Resposta do Gemini: o texto JSON, ou o estado HTTP do erro. */
export type Generated = { text: string } | { status: number };

export type Part = { text: string } | { inlineData: { mimeType: string; data: string } };

const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
const envKey = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
const geminiKey = Deno.env.get('GEMINI_API_KEY') ?? '';
// O alias "-latest" segue o modelo atual da família, sem mudar o código.
const model = Deno.env.get('GEMINI_MODEL') || 'gemini-flash-lite-latest';

export const geminiConfigured = geminiKey !== '';

/** A base valida o token, a allowlist e a quota (`claim_photo_ai_quota`). */
export async function claimQuota(authorization: string, apiKey: string | null): Promise<Quota> {
  const res = await fetch(`${supabaseUrl}/rest/v1/rpc/claim_photo_ai_quota`, {
    method: 'POST',
    headers: { apikey: apiKey ?? envKey, authorization, 'content-type': 'application/json' },
    body: '{}',
  });
  if (res.status === 401 || res.status === 403) {
    await res.body?.cancel();
    return 'unauthorized';
  }
  if (!res.ok) {
    await res.body?.cancel();
    throw new Error(`claim_photo_ai_quota: ${res.status}`);
  }
  const value = await res.json();
  return value === 'ok' || value === 'forbidden' || value === 'rate_limited'
    ? value
    : 'unauthorized';
}

/** Um pedido ao Gemini com a resposta presa a [schema]. */
export async function generate(
  parts: Part[],
  schema: unknown,
  temperature = 0,
): Promise<Generated> {
  const res = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`,
    {
      method: 'POST',
      headers: { 'x-goog-api-key': geminiKey, 'content-type': 'application/json' },
      body: JSON.stringify({
        contents: [{ role: 'user', parts }],
        generationConfig: {
          responseMimeType: 'application/json',
          responseSchema: schema,
          temperature,
        },
      }),
      signal: AbortSignal.timeout(30_000),
    },
  );
  if (!res.ok) {
    // Sem a chave nem o conteúdo no registo: só o estado.
    console.error(`gemini ${res.status}`);
    await res.body?.cancel();
    return { status: res.status };
  }
  const out = await res.json();
  const text = out?.candidates?.[0]?.content?.parts
    ?.map((p: { text?: string }) => p.text ?? '')
    .join('');
  return typeof text === 'string' && text.length > 0 ? { text } : { status: 502 };
}
