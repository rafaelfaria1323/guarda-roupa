// Edge Function `describe-photo` (docs/features/ia-gemini.md): lê uma foto
// com o Gemini (opcional, ligado pelo utilizador) e devolve só valores que a
// app conhece. A foto não fica guardada aqui.
import {
  CATEGORIES,
  COLORS,
  FORMALITY,
  GARMENT_PROMPT,
  GARMENT_SCHEMA,
  LABEL_PROMPT,
  LABEL_SCHEMA,
  PATTERNS,
  TEXTURES,
  WARMTH,
  WASH,
} from './schema.ts';

export type Kind = 'garment' | 'label';
export type Quota = 'ok' | 'forbidden' | 'rate_limited' | 'unauthorized';

/** Resposta do Gemini: o texto JSON, ou o estado HTTP do erro. */
export type Generated = { text: string } | { status: number };

export interface Deps {
  /** Há chave do Gemini nos secrets. */
  configured: boolean;
  claimQuota(authorization: string, apiKey: string | null): Promise<Quota>;
  generate(
    prompt: string,
    schema: unknown,
    image: { mimeType: string; data: string },
  ): Promise<Generated>;
}

/** ~1,5 MB de JPEG em base64. */
const MAX_IMAGE = 2_100_000;
const MIME = ['image/jpeg', 'image/png', 'image/webp'];

const CORS = {
  'access-control-allow-origin': '*',
  'access-control-allow-headers': 'authorization, apikey, content-type, x-client-info',
  'access-control-allow-methods': 'POST, OPTIONS',
};

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, 'content-type': 'application/json' },
  });
}

export async function handle(req: Request, deps: Deps): Promise<Response> {
  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: CORS });
  if (req.method !== 'POST') return json(405, { error: 'method' });
  if (!deps.configured) return json(503, { error: 'not_configured' });

  const authorization = req.headers.get('authorization');
  if (authorization == null || !authorization.startsWith('Bearer ')) {
    return json(401, { error: 'unauthorized' });
  }
  let body: { kind?: unknown; image?: unknown; mime?: unknown };
  try {
    body = await req.json();
  } catch {
    return json(400, { error: 'bad_request' });
  }
  const kind = body.kind;
  const image = body.image;
  const mime = body.mime ?? 'image/jpeg';
  if (
    (kind !== 'garment' && kind !== 'label') ||
    typeof image !== 'string' || image.length < 100 || image.length > MAX_IMAGE ||
    !/^[A-Za-z0-9+/]+=*$/.test(image) ||
    typeof mime !== 'string' || !MIME.includes(mime)
  ) {
    return json(400, { error: 'bad_request' });
  }

  const quota = await deps.claimQuota(authorization, req.headers.get('apikey'));
  if (quota === 'unauthorized') return json(401, { error: 'unauthorized' });
  if (quota === 'forbidden') return json(403, { error: 'forbidden' });
  if (quota === 'rate_limited') return json(429, { error: 'rate_limited' });

  let generated: Generated;
  try {
    generated = await deps.generate(
      kind === 'garment' ? GARMENT_PROMPT : LABEL_PROMPT,
      kind === 'garment' ? GARMENT_SCHEMA : LABEL_SCHEMA,
      { mimeType: mime, data: image },
    );
  } catch {
    return json(502, { error: 'failed' });
  }
  if ('status' in generated) {
    // 429 do Gemini: acabou a quota grátis (por minuto ou por dia).
    return json(generated.status === 429 ? 429 : 502, {
      error: generated.status === 429 ? 'busy' : 'failed',
    });
  }
  let raw: unknown;
  try {
    raw = JSON.parse(generated.text);
  } catch {
    return json(502, { error: 'failed' });
  }
  return json(200, kind === 'garment' ? garmentOf(raw) : labelOf(raw));
}

const pick = <T extends string>(values: readonly T[], v: unknown): T | null =>
  typeof v === 'string' && (values as readonly string[]).includes(v) ? v as T : null;

function text(v: unknown, max: number): string | null {
  if (typeof v !== 'string') return null;
  const t = v.replace(/\s+/g, ' ').trim();
  return t.length === 0 ? null : t.slice(0, max).trim();
}

/** Só valores conhecidos; cores: até 3, sem repetir, em passos de 5 e soma ≤ 100. */
export function garmentOf(raw: unknown) {
  const r = (raw ?? {}) as Record<string, unknown>;
  const colors: { color: string; share: number }[] = [];
  let total = 0;
  for (const c of Array.isArray(r.colors) ? r.colors : []) {
    const color = pick(COLORS, (c as Record<string, unknown>)?.color);
    const share = Number((c as Record<string, unknown>)?.share);
    if (color == null || !Number.isFinite(share) || colors.some((x) => x.color === color)) {
      continue;
    }
    const step = Math.min(100 - total, Math.max(5, Math.round(share / 5) * 5));
    if (step <= 0 || colors.length === 3) break;
    colors.push({ color, share: step });
    total += step;
  }
  return {
    category: pick(CATEGORIES, r.category),
    name: text(r.name, 60),
    colors,
    pattern: pick(PATTERNS, r.pattern),
    texture: pick(TEXTURES, r.texture),
    warmth: pick(WARMTH, r.warmth),
    formality: pick(FORMALITY, r.formality),
  };
}

export function labelOf(raw: unknown) {
  const r = (raw ?? {}) as Record<string, unknown>;
  return {
    wash: pick(WASH, r.wash),
    tumble_dry: typeof r.tumble_dry === 'boolean' ? r.tumble_dry : null,
    material: text(r.material, 120),
    care: text(r.care, 300),
  };
}
