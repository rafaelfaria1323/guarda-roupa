// "Peças que faziam falta" (docs/features/pecas-em-falta.md): o Gemini lê o
// armário e as inspirações (só texto) e sugere peças para comprar, com
// marcas ao nível das que a pessoa já tem, mais baratas e mais caras. Nunca
// modelos nem preços: a app abre uma pesquisa com o texto sugerido.
import { CATEGORIES, COLORS } from '../describe-photo/schema.ts';

export const TIERS = ['same', 'cheaper', 'pricier'] as const;
const GROUPS = ['top', 'bottom', 'onePiece', 'outerwear', 'footwear', 'accessory', 'other'];
const REASONS = [
  'missingGroup',
  'onlyLight',
  'onlyDark',
  'inspirationColor',
  'inspirationDressy',
  'fewBottoms',
];

export const SHOPPING_SCHEMA = {
  type: 'OBJECT',
  properties: {
    ideas: {
      type: 'ARRAY',
      items: {
        type: 'OBJECT',
        properties: {
          category: { type: 'STRING', enum: [...CATEGORIES] },
          color: { type: 'STRING', enum: [...COLORS] },
          title: { type: 'STRING' },
          why: { type: 'STRING' },
          search: { type: 'STRING' },
          brands: {
            type: 'ARRAY',
            items: {
              type: 'OBJECT',
              properties: {
                name: { type: 'STRING' },
                tier: { type: 'STRING', enum: [...TIERS] },
              },
              required: ['name', 'tier'],
            },
          },
        },
        required: ['category', 'title', 'why', 'search', 'brands'],
      },
    },
  },
  required: ['ideas'],
};

export const SHOPPING_PROMPT =
  `You are a personal stylist helping someone decide what to buy next. Below are their wardrobe (no photos), their style inspirations (tags they confirmed), gaps the app found, the brands they own, an optional budget per item in euros and ideas they already dismissed.
Suggest 3 to 5 items that would add the most outfits, prioritising the app's gaps and what repeats in the inspirations. Never suggest something they already own in the same color and category, nor a dismissed idea.
For each idea:
- "category" and "color" from the allowed values.
- "title": a concrete description in European Portuguese (pt-PT), at most 8 words (e.g. "Ténis pretos em pele, sola fina").
- "why": 1 or 2 short sentences in pt-PT naming what it goes with (their items or inspirations). No ids.
- "search": a short shop search text in pt-PT, without brand (e.g. "ténis pretos pele minimalistas").
- "brands": 3 or 4 real, well-known brands that sell this kind of item in Portugal or online in Europe: at least one at the same price level as the brands they own ("same"), one cheaper ("cheaper") and one more expensive ("pricier"). Respect the budget for "same" and "cheaper" when given. If they own no brands, assume mid-market high-street. Brand names only: no product models, prices or links.
`;

const str = (v: unknown, max: number): string | null =>
  typeof v === 'string' && v.trim() !== ''
    ? v.replace(/\s+/g, ' ').trim().slice(0, max).trim()
    : null;
const strs = (v: unknown, n: number, max: number): string[] =>
  Array.isArray(v)
    ? v.map((x) => str(x, max)).filter((x): x is string => x != null).slice(0, n)
    : [];
const pickIn = (values: readonly string[], v: unknown): string | null =>
  typeof v === 'string' && values.includes(v) ? v : null;

/** O pedido limpo, ou `null` se não serve (antes de gastar quota). */
/** Uma inspiração em texto: só as etiquetas, com tamanhos limitados. */
export function inspirationOf(x: unknown) {
  const i = (x ?? {}) as Record<string, unknown>;
  return {
    title: str(i.title, 80),
    palette: strs(i.palette, 6, 20),
    formality: str(i.formality, 20),
    patterns: strs(i.patterns, 6, 20),
    textures: strs(i.textures, 6, 20),
    occasions: strs(i.occasions, 3, 20),
    proportions: strs(i.proportions, 6, 40),
  };
}

export function shoppingBriefOf(body: Record<string, unknown>) {
  const raw = Array.isArray(body.garments) ? body.garments : null;
  if (raw == null || raw.length > 300) return null;
  const garments = raw.map((x) => {
    const g = (x ?? {}) as Record<string, unknown>;
    const category = pickIn(CATEGORIES, g.category);
    if (category == null) return null;
    const out: Record<string, unknown> = { category };
    const name = str(g.name, 60);
    if (name != null) out.name = name;
    const brand = str(g.brand, 40);
    if (brand != null) out.brand = brand;
    const formality = str(g.formality, 20);
    if (formality != null) out.formality = formality;
    out.colors = strs(g.colors, 3, 20);
    return out;
  });
  if (garments.some((g) => g == null)) return null;
  const inspirations = (Array.isArray(body.inspirations) ? body.inspirations : [])
    .slice(0, 40)
    .map(inspirationOf);
  const gaps = (Array.isArray(body.gaps) ? body.gaps : []).slice(0, 10).flatMap((x) => {
    const g = (x ?? {}) as Record<string, unknown>;
    const reason = pickIn(REASONS, g.reason);
    if (reason == null) return [];
    return [{
      reason,
      group: pickIn(GROUPS, g.group),
      color: pickIn(COLORS, g.color),
      inspirations: typeof g.inspirations === 'number' ? Math.min(99, g.inspirations) : 0,
    }];
  });
  const budget = typeof body.budget_eur === 'number' && Number.isFinite(body.budget_eur)
    ? Math.min(5000, Math.max(5, Math.round(body.budget_eur)))
    : null;
  return {
    wardrobe: garments,
    inspirations,
    gaps,
    brands_owned: [...new Set(garments.map((g) => g!.brand).filter((b) => b != null))].slice(
      0,
      30,
    ),
    budget_eur: budget,
    dismissed: strs(body.dismissed, 30, 60),
  };
}

/** Só ideias com categoria conhecida, texto e pelo menos uma marca. */
export function ideasOf(raw: unknown) {
  const r = (raw ?? {}) as Record<string, unknown>;
  const ideas = [];
  for (const x of Array.isArray(r.ideas) ? r.ideas : []) {
    const i = (x ?? {}) as Record<string, unknown>;
    const category = pickIn(CATEGORIES, i.category);
    const title = str(i.title, 80);
    const search = str(i.search, 80);
    if (category == null || title == null || search == null) continue;
    const brands: { name: string; tier: string }[] = [];
    for (const b of Array.isArray(i.brands) ? i.brands : []) {
      const name = str((b as Record<string, unknown>)?.name, 30);
      const tier = pickIn(TIERS, (b as Record<string, unknown>)?.tier);
      if (name == null || tier == null || brands.some((x) => x.name === name)) continue;
      brands.push({ name, tier });
      if (brands.length === 4) break;
    }
    if (brands.length === 0) continue;
    ideas.push({
      category,
      color: pickIn(COLORS, i.color),
      title,
      why: str(i.why, 300),
      search,
      brands,
    });
    if (ideas.length === 5) break;
  }
  return ideas;
}
