/**
 * Sites de inspiração (Pinterest, Instagram): uma página destes, partilhada
 * pelo atalho do iPhone, é uma **inspiração**, não uma peça
 * (docs/features/inspiracoes-e-estilo.md#pinterest).
 *
 * O fio nunca pede páginas nem imagens a estes sites: o robots.txt do
 * Pinterest recusa qualquer leitor automático (`User-agent: *` →
 * `Disallow: /`). Só se usa o que o utilizador abriu no próprio Safari e o
 * atalho mandou: o link, o título e a descrição.
 */
import type { SharedPage } from './shared_page.ts';

export interface InspirationSite {
  id: string;
  name: string;
}

/** O site de inspiração deste domínio, ou `null`. */
export function inspirationSite(host: string): InspirationSite | null {
  const h = host.toLowerCase();
  // pinterest.com, pt.pinterest.com, pinterest.pt, pinterest.co.uk, pin.it…
  if (h === 'pin.it' || /(^|\.)pinterest\.[a-z]{2,3}(\.[a-z]{2})?$/.test(h)) {
    return { id: 'pinterest', name: 'Pinterest' };
  }
  if (h === 'instagram.com' || h.endsWith('.instagram.com')) {
    return { id: 'instagram', name: 'Instagram' };
  }
  return null;
}

export const INSPIRATION_LIMITS = { title: 120, description: 1000 };

export interface SharedInspiration {
  url: string;
  title?: string;
  description?: string;
}

/**
 * Link, título e descrição da página partilhada. O link canónico
 * (`og:url`) só substitui o da página se for do mesmo site, em https.
 */
export function readInspiration(
  page: SharedPage,
  url: URL,
  site: InspirationSite,
): SharedInspiration {
  const meta = (key: string) =>
    page.meta.find(([k, v]) => k.toLowerCase() === key && v.trim() !== '')?.[1].trim();
  let link = url.href;
  const canonical = meta('og:url');
  if (canonical != null) {
    try {
      const c = new URL(canonical);
      if (c.protocol === 'https:' && inspirationSite(c.hostname)?.id === site.id) link = c.href;
    } catch {
      // Fica o link da página.
    }
  }
  const title = clean(meta('og:title') ?? meta('twitter:title') ?? page.title, site);
  const description = meta('og:description') ?? meta('description');
  return {
    url: link,
    title: cut(title, INSPIRATION_LIMITS.title),
    description: cut(description, INSPIRATION_LIMITS.description),
  };
}

/** Tira o nome do site do fim do título ("… | Pinterest"). */
function clean(title: string | undefined, site: InspirationSite): string | undefined {
  if (title == null) return undefined;
  const t = title.replace(new RegExp(`\\s*[|·•–-]\\s*${site.name}\\s*$`, 'i'), '').trim();
  return t === '' || t.toLowerCase() === site.name.toLowerCase() ? undefined : t;
}

function cut(s: string | undefined, max: number): string | undefined {
  if (s == null) return undefined;
  const t = s.replace(/\s+/g, ' ').trim();
  if (t === '') return undefined;
  return t.length <= max ? t : `${t.slice(0, max - 1).trimEnd()}…`;
}
