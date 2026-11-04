/**
 * Dados de produto a partir de uma página (JSON-LD `Product`/`ProductGroup`,
 * com Open Graph como alternativa parcial). Só texto: nada do HTML é
 * executado nem devolvido como HTML. Preço e stock não interessam.
 */

export type Source = 'json-ld' | 'open-graph';

export interface Variant {
  color?: string;
  size?: string;
  sku?: string;
  image?: string;
}

export interface ProductPreview {
  name?: string;
  brand?: string;
  description?: string;
  color?: string;
  material?: string;
  images: string[];
  variants: Variant[];
  /** De onde veio cada campo preenchido. */
  sources: Record<string, Source>;
  /** O que o utilizador tem de confirmar antes de criar a peça. */
  confirm: string[];
}

const MAX = { name: 200, text: 2000, short: 120, images: 12, variants: 40 };

export function parseProduct(
  html: string,
  pageUrl: URL,
): ProductPreview | null {
  const ld = jsonLdProduct(html);
  const og = openGraph(html);
  const out: ProductPreview = {
    images: [],
    variants: [],
    sources: {},
    confirm: [],
  };
  const set = (
    field: 'name' | 'brand' | 'description' | 'color' | 'material',
    value: string | undefined,
    source: Source,
    max = MAX.short,
  ) => {
    const v = clean(value, max);
    if (v == null || out[field] != null) return;
    out[field] = v;
    out.sources[field] = source;
  };

  if (ld != null) {
    set('name', text(ld.name), 'json-ld', MAX.name);
    set('brand', brandOf(ld.brand), 'json-ld');
    set('description', text(ld.description), 'json-ld', MAX.text);
    set('color', text(ld.color), 'json-ld');
    set('material', text(ld.material), 'json-ld');
    addImages(out, imagesOf(ld.image), pageUrl, 'json-ld');
    for (const v of asArray(ld.hasVariant)) {
      if (!isObject(v) || out.variants.length >= MAX.variants) continue;
      const image = imagesOf(v.image)
        .map((i) => absolute(i, pageUrl))
        .find((i) => i != null);
      const variant: Variant = {
        color: clean(text(v.color), MAX.short),
        size: clean(text(v.size), MAX.short),
        sku: clean(text(v.sku), MAX.short),
        image: image ?? undefined,
      };
      if (Object.values(variant).some((x) => x != null)) {
        out.variants.push(variant);
      }
    }
  }
  set('name', og.meta['og:title'], 'open-graph', MAX.name);
  set('brand', og.meta['product:brand'], 'open-graph');
  set('description', og.meta['og:description'], 'open-graph', MAX.text);
  set('color', og.meta['product:color'], 'open-graph');
  addImages(out, og.images, pageUrl, 'open-graph');

  if (out.name == null && out.images.length === 0) return null;

  // A categoria, as cores e a posse confirmam-se sempre; a variante quando
  // a página tem várias (várias cores não dizem qual é a tua).
  out.confirm = ['category', 'colors', 'owned'];
  const colors = new Set(out.variants.map((v) => v.color).filter(Boolean));
  if (colors.size > 1 || out.variants.length > 1) out.confirm.push('variant');
  if (out.material == null) out.confirm.push('material');
  return out;
}

type Json = Record<string, unknown>;

function jsonLdProduct(html: string): Json | null {
  const re = /<script\b[^>]*type\s*=\s*["']?application\/ld\+json["']?[^>]*>([\s\S]*?)<\/script>/gi;
  let fallback: Json | null = null;
  for (const m of html.matchAll(re)) {
    let data: unknown;
    try {
      data = JSON.parse(m[1].trim());
    } catch {
      continue;
    }
    for (const node of flatten(data)) {
      const types = asArray(node['@type']).map(String);
      if (types.includes('ProductGroup')) return node;
      if (types.includes('Product')) fallback ??= node;
    }
  }
  return fallback;
}

function flatten(data: unknown): Json[] {
  const out: Json[] = [];
  const visit = (x: unknown, depth: number) => {
    if (depth > 4) return;
    if (Array.isArray(x)) {
      for (const i of x) visit(i, depth + 1);
    } else if (isObject(x)) {
      out.push(x);
      if (x['@graph'] != null) visit(x['@graph'], depth + 1);
    }
  };
  visit(data, 0);
  return out;
}

interface OpenGraph {
  meta: Record<string, string>;
  images: string[];
}

function openGraph(html: string): OpenGraph {
  const out: OpenGraph = { meta: {}, images: [] };
  for (const m of html.matchAll(/<meta\b[^>]*>/gi)) {
    const attrs = attributes(m[0]);
    const key = (attrs.property ?? attrs.name ?? '').toLowerCase();
    const content = attrs.content;
    if (key === '' || content == null) continue;
    if (key === 'og:image' || key === 'og:image:secure_url') {
      out.images.push(content);
    } else if (out.meta[key] == null) {
      out.meta[key] = content;
    }
  }
  return out;
}

function attributes(tag: string): Record<string, string> {
  const out: Record<string, string> = {};
  for (const m of tag.matchAll(/([a-zA-Z:_-]+)\s*=\s*("([^"]*)"|'([^']*)')/g)) {
    out[m[1].toLowerCase()] = decodeEntities(m[3] ?? m[4] ?? '');
  }
  return out;
}

function addImages(
  out: ProductPreview,
  images: string[],
  pageUrl: URL,
  source: Source,
) {
  for (const raw of images) {
    if (out.images.length >= MAX.images) return;
    const url = absolute(raw, pageUrl);
    if (url == null || out.images.includes(url)) continue;
    out.images.push(url);
    out.sources.images ??= source;
  }
}

function absolute(raw: string, base: URL): string | null {
  try {
    const url = new URL(decodeEntities(raw.trim()), base);
    return url.protocol === 'https:' ? url.href : null;
  } catch {
    return null;
  }
}

function imagesOf(x: unknown): string[] {
  return asArray(x).flatMap((i) => {
    if (typeof i === 'string') return [i];
    if (isObject(i)) {
      const url = i.contentUrl ?? i.url;
      return typeof url === 'string' ? [url] : [];
    }
    return [];
  });
}

function brandOf(x: unknown): string | undefined {
  const b = asArray(x)[0];
  if (typeof b === 'string') return b;
  if (isObject(b)) return text(b.name);
  return undefined;
}

function text(x: unknown): string | undefined {
  const v = asArray(x)[0];
  if (typeof v === 'string') return v;
  if (typeof v === 'number') return String(v);
  if (isObject(v)) return text(v.name ?? v['@value']);
  return undefined;
}

/** Sem etiquetas, entidades descodificadas, espaços normalizados. */
function clean(x: string | undefined, max: number): string | undefined {
  if (x == null) return undefined;
  const v = decodeEntities(x.replace(/<[^>]*>/g, ' '))
    // deno-lint-ignore no-control-regex
    .replace(/[\u0000-\u001f\u007f]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
  if (v === '') return undefined;
  return v.length > max ? `${v.slice(0, max - 1)}…` : v;
}

const NAMED: Record<string, string> = {
  amp: '&',
  lt: '<',
  gt: '>',
  quot: '"',
  apos: "'",
  nbsp: ' ',
};

function decodeEntities(s: string): string {
  return s.replace(/&(#x[0-9a-f]+|#[0-9]+|[a-z]+);/gi, (all, e: string) => {
    if (e[0] === '#') {
      const code = e[1] === 'x' || e[1] === 'X'
        ? parseInt(e.slice(2), 16)
        : parseInt(e.slice(1), 10);
      return Number.isFinite(code) && code > 0 && code <= 0x10ffff
        ? String.fromCodePoint(code)
        : all;
    }
    return NAMED[e.toLowerCase()] ?? all;
  });
}

function asArray(x: unknown): unknown[] {
  return x == null ? [] : Array.isArray(x) ? x : [x];
}

function isObject(x: unknown): x is Json {
  return typeof x === 'object' && x != null && !Array.isArray(x);
}
