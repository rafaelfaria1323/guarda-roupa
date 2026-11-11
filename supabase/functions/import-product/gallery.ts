/**
 * A galeria da página partilhada pelo atalho: os endereços das imagens que
 * o Safari mostrava. Muitas lojas só põem uma foto nos dados estruturados
 * e o resto da galeria fica nas imagens da página. Daqui só ficam as do
 * mesmo produto, para a pessoa escolher quais guarda.
 */

/** Quantos endereços o atalho pode mandar e quantas fotos ficam no fim. */
export const GALLERY_LIMITS = { urls: 60, urlLength: 2048, images: 12 };

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
 * Junta às fotos do produto as da galeria que são do mesmo produto: as que
 * têm a referência da foto principal no nome (`04749700800` na Zara) ou,
 * sem referência, as da mesma pasta. A mesma foto noutro tamanho conta uma
 * vez só. Bolinhas de cor e ícones (`chip`, `swatch`…) ficam de fora.
 */
export function withGallery(images: string[], gallery: string[]): string[] {
  const main = images[0];
  if (main == null || gallery.length === 0) return images;
  const mainUrl = new URL(main);
  const file = mainUrl.pathname.split('/').pop() ?? '';
  const ref = (file.match(/\d{5,}/g) ?? []).sort((a, b) => b.length - a.length)[0];
  const dir = mainUrl.pathname.slice(0, mainUrl.pathname.lastIndexOf('/') + 1);
  const sameProduct = (u: URL) =>
    u.host === mainUrl.host &&
    (ref != null
      ? u.pathname.includes(ref)
      : u.pathname.startsWith(dir) && /\.(jpe?g|png|webp|avif)$/i.test(u.pathname));

  const icon = /(chip|swatch|icon|logo|sprite|placeholder)/i;
  const key = (u: URL) => u.host + u.pathname;
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
