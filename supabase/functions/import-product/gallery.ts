/**
 * A galeria da página partilhada pelo atalho: os endereços das imagens que
 * o Safari mostrava. Muitas lojas só põem uma foto nos dados estruturados
 * e o resto da galeria fica nas imagens da página. Daqui só ficam as do
 * mesmo produto, para a pessoa escolher quais guarda.
 */

/** Quantos endereços o atalho pode mandar e quantas fotos ficam no fim. */
export const GALLERY_LIMITS = { urls: 60, urlLength: 2048, images: 12, more: 24 };

/** Os endereços `https` da galeria; o que não servir fica de fora. */
export function readGallery(raw: unknown): string[] {
  if (!Array.isArray(raw)) return [];
  const out: string[] = [];
  for (const u of raw.slice(0, GALLERY_LIMITS.urls)) {
    if (typeof u !== 'string' || u.length > GALLERY_LIMITS.urlLength) continue;
    try {
      const url = new URL(u);
      if (url.protocol === 'https:' && !out.includes(url.href)) out.push(url.href);
    } catch {
      // Não é um endereço.
    }
  }
  return out;
}

/**
 * Junta às fotos do produto as da galeria que são do mesmo produto, no
 * mesmo servidor que a foto principal (ou que a página):
 *
 * - com a referência do link da página no nome (`2003199` na Gant em
 *   `/p/t-shirt…/2003199-110`, `04749700` na Zara em `…-p04749700.html`);
 * - sem referência no link, com a da foto principal (o número mais
 *   comprido do nome) ou, sem nenhuma, na mesma pasta.
 *
 * A mesma foto noutro tamanho ou noutro endereço (o mesmo nome de ficheiro)
 * conta uma vez só. Bolinhas de cor e ícones (`chip`, `swatch`…) ficam de fora.
 */
export function withGallery(images: string[], gallery: string[], pageUrl?: URL): string[] {
  const main = images[0];
  if (main == null || gallery.length === 0) return images;
  const mainUrl = new URL(main);
  const runs = (s: string) => s.match(/\d{5,}/g) ?? [];
  const pageRefs = pageUrl == null ? [] : runs(pageUrl.pathname);
  const file = (u: URL) => u.pathname.split('/').pop() ?? '';
  const mainRef = runs(file(mainUrl)).sort((a, b) => b.length - a.length)[0];
  const refs = pageRefs.length > 0 ? pageRefs : mainRef == null ? [] : [mainRef];
  const dir = mainUrl.pathname.slice(0, mainUrl.pathname.lastIndexOf('/') + 1);
  const hosts = new Set([mainUrl.host, pageUrl?.host]);
  const sameProduct = (u: URL) =>
    hosts.has(u.host) &&
    (refs.length > 0
      ? refs.some((r) => u.pathname.includes(r))
      : u.pathname.startsWith(dir) && /\.(jpe?g|png|webp|avif)$/i.test(u.pathname));

  const icon = /(chip|swatch|icon|logo|sprite|placeholder)/i;
  const key = (u: URL) => file(u).toLowerCase();
  const out = [...images];
  const seen = new Set(images.map((i) => key(new URL(i))));
  for (const g of gallery) {
    if (out.length >= GALLERY_LIMITS.images) break;
    const u = new URL(g);
    if (seen.has(key(u)) || icon.test(u.pathname) || !sameProduct(u)) continue;
    seen.add(key(u));
    out.push(u.href);
  }
  return out;
}

/**
 * As outras imagens da página, para "Ver todas as imagens": o que o filtro
 * de [withGallery] deixou de fora (menos ícones e repetidas). É a saída
 * para quando o filtro falha numa loja nova.
 */
export function restOfGallery(images: string[], gallery: string[]): string[] {
  const file = (u: string) => (new URL(u).pathname.split('/').pop() ?? '').toLowerCase();
  const seen = new Set(images.map(file));
  const out: string[] = [];
  for (const g of gallery) {
    if (out.length >= GALLERY_LIMITS.more) break;
    const u = new URL(g);
    if (seen.has(file(g)) || /(chip|swatch|icon|logo|sprite|placeholder)/i.test(u.pathname)) {
      continue;
    }
    seen.add(file(g));
    out.push(u.href);
  }
  return out;
}
