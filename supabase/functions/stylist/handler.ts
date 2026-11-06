// Edge Function `stylist` (docs/features/ia-gemini.md): o Gemini escolhe um
// conjunto só com as peças que a app manda (texto, sem fotos) e explica
// porquê. Devolve só peças e papéis válidos; a app volta a verificar.
import type { Generated, Quota } from '../_shared/gemini.ts';

export interface Deps {
  configured: boolean;
  claimQuota(authorization: string, apiKey: string | null): Promise<Quota>;
  generate(prompt: string, schema: unknown): Promise<Generated>;
}

export const ROLES = [
  'main_top',
  'mid_layer',
  'outer_layer',
  'bottom',
  'one_piece',
  'footwear',
  'accessory',
] as const;
const OCCASIONS = ['casual', 'work_casual', 'evening'];
const MAX_GARMENTS = 200;
const ID = /^p\d{1,3}$/;

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

export const SCHEMA = {
  type: 'OBJECT',
  properties: {
    name: { type: 'STRING' },
    items: {
      type: 'ARRAY',
      items: {
        type: 'OBJECT',
        properties: {
          id: { type: 'STRING' },
          role: { type: 'STRING', enum: [...ROLES] },
        },
        required: ['id', 'role'],
      },
    },
    why: { type: 'STRING' },
  },
  required: ['name', 'items', 'why'],
};

const PROMPT =
  `You are a personal stylist. Build ONE outfit for today using ONLY items from the wardrobe below (refer to them by "id").
Rules:
- Either main_top + bottom, or one_piece. Add footwear. A knit (sweater, sweatshirt, cardigan) worn over another top is mid_layer, with a light top as main_top under it.
- Add outer_layer when it is cold or rainy. Accessories (umbrella, scarf, sunglasses, ...) only when the weather or the look asks for them.
- Respect the weather (feels_like_c in °C), the occasion and the user's likes and avoids. Prefer items worn less recently ("last_worn_days"; null = never worn).
- Think about color harmony, proportions (fit, length) and a coherent formality.
- If "previous" is given, propose something clearly different, unless "ask" asks to adjust it.
- If "ask" is given, follow it when possible.
- "name": a short outfit name in European Portuguese (pt-PT), at most 5 words.
- "why": 1 to 3 short sentences in European Portuguese (pt-PT), friendly, explaining why it works today. No ids in the text.
`;

const str = (v: unknown, max: number): string | null =>
  typeof v === 'string' && v.trim() !== '' ? v.trim().slice(0, max) : null;
const strs = (v: unknown, n: number, max: number): string[] =>
  Array.isArray(v)
    ? v.map((x) => str(x, max)).filter((x): x is string => x != null).slice(0, n)
    : [];
const num = (v: unknown, min: number, max: number): number | null =>
  typeof v === 'number' && Number.isFinite(v) ? Math.min(max, Math.max(min, v)) : null;

/** Só os campos conhecidos de cada peça, com tamanhos limitados. */
function garmentOf(raw: unknown): Record<string, unknown> | null {
  const g = (raw ?? {}) as Record<string, unknown>;
  if (typeof g.id !== 'string' || !ID.test(g.id)) return null;
  const category = str(g.category, 30);
  if (category == null) return null;
  const out: Record<string, unknown> = { id: g.id, category };
  for (const k of ['name', 'pattern', 'texture', 'warmth', 'formality', 'fit', 'length']) {
    const v = str(g[k], k === 'name' ? 60 : 20);
    if (v != null) out[k] = v;
  }
  const colors = strs(g.colors, 3, 20);
  if (colors.length > 0) out.colors = colors;
  const occasions = strs(g.occasions, 3, 20);
  if (occasions.length > 0) out.occasions = occasions;
  for (const k of ['rain_ok', 'wind_ok']) if (typeof g[k] === 'boolean') out[k] = g[k];
  out.wears_30d = num(g.wears_30d, 0, 99) ?? 0;
  out.last_worn_days = num(g.last_worn_days, 0, 9999);
  return out;
}

export async function handle(req: Request, deps: Deps): Promise<Response> {
  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: CORS });
  if (req.method !== 'POST') return json(405, { error: 'method' });
  if (!deps.configured) return json(503, { error: 'not_configured' });

  const authorization = req.headers.get('authorization');
  if (authorization == null || !authorization.startsWith('Bearer ')) {
    return json(401, { error: 'unauthorized' });
  }
  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json(400, { error: 'bad_request' });
  }
  const raw = Array.isArray(body?.garments) ? body.garments : null;
  if (raw == null || raw.length < 2 || raw.length > MAX_GARMENTS) {
    return json(400, { error: 'bad_request' });
  }
  const garments = raw.map(garmentOf);
  const ids = new Set<string>();
  for (const g of garments) {
    if (g == null || ids.has(g.id as string)) return json(400, { error: 'bad_request' });
    ids.add(g.id as string);
  }
  const occasion = typeof body.occasion === 'string' && OCCASIONS.includes(body.occasion)
    ? body.occasion
    : null;
  const w = (body.weather ?? null) as Record<string, unknown> | null;
  const weather = w == null ? null : {
    feels_like_c: num(w.feels_like_c, -40, 55),
    rain: w.rain === true,
    wind_kmh: num(w.wind_kmh, 0, 200) ?? 0,
    sunny: w.sunny === true,
  };
  const brief = {
    occasion,
    weather,
    likes: strs(body.likes, 20, 40),
    avoids: strs(body.avoids, 20, 40),
    previous: strs(body.previous, 10, 5).filter((id) => ids.has(id)),
    ask: str(body.ask, 200),
    wardrobe: garments,
  };

  const quota = await deps.claimQuota(authorization, req.headers.get('apikey'));
  if (quota === 'unauthorized') return json(401, { error: 'unauthorized' });
  if (quota === 'forbidden') return json(403, { error: 'forbidden' });
  if (quota === 'rate_limited') return json(429, { error: 'rate_limited' });

  let generated: Generated;
  try {
    generated = await deps.generate(`${PROMPT}\n${JSON.stringify(brief)}`, SCHEMA);
  } catch {
    return json(502, { error: 'failed' });
  }
  if ('status' in generated) {
    return json(generated.status === 429 ? 429 : 502, {
      error: generated.status === 429 ? 'busy' : 'failed',
    });
  }
  let out: unknown;
  try {
    out = JSON.parse(generated.text);
  } catch {
    return json(502, { error: 'failed' });
  }
  const pick = pickOf(out, ids);
  return pick == null ? json(502, { error: 'failed' }) : json(200, pick);
}

/** Só peças que foram mandadas, sem repetir, com papéis conhecidos. */
export function pickOf(raw: unknown, ids: Set<string>) {
  const r = (raw ?? {}) as Record<string, unknown>;
  const items: { id: string; role: string }[] = [];
  for (const i of Array.isArray(r.items) ? r.items : []) {
    const id = (i as Record<string, unknown>)?.id;
    const role = (i as Record<string, unknown>)?.role;
    if (
      typeof id !== 'string' || !ids.has(id) || items.some((x) => x.id === id) ||
      typeof role !== 'string' || !(ROLES as readonly string[]).includes(role)
    ) continue;
    items.push({ id, role });
    if (items.length === 8) break;
  }
  if (items.length === 0) return null;
  const text = (v: unknown, max: number) =>
    typeof v === 'string' ? v.replace(/\s+/g, ' ').trim().slice(0, max).trim() || null : null;
  return { name: text(r.name, 60), items, why: text(r.why, 400) };
}
