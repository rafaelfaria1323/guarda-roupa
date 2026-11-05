/**
 * A página que o utilizador abriu no próprio browser e partilhou com o
 * atalho do iPhone ("Importar para o fio"): os blocos JSON-LD, as meta tags
 * e o título, já lidos pelo Safari. Serve as lojas que bloqueiam pedidos
 * automáticos (Zara, Massimo Dutti) sem contornar nada: a função não pede a
 * página, só lê o que o utilizador lhe deu.
 *
 * Os dados vêm do cliente, por isso são limitados e tratados como texto. A
 * página é remontada como HTML mínimo para passar pelo mesmo parser.
 */
export interface SharedPage {
  title?: string;
  ld: string[];
  meta: [string, string][];
}

export const SHARED_LIMITS = {
  title: 500,
  ldBlocks: 10,
  ldBytes: 200_000,
  metaTags: 80,
  metaValue: 2_000,
};

/** O `page` do pedido, validado; `null` se não tiver a forma certa. */
export function readSharedPage(raw: unknown): SharedPage | null {
  if (typeof raw !== 'object' || raw == null || Array.isArray(raw)) return null;
  const o = raw as Record<string, unknown>;
  const title = o.title;
  if (title != null && typeof title !== 'string') return null;
  const ld = o.ld ?? [];
  const meta = o.meta ?? [];
  if (!Array.isArray(ld) || !Array.isArray(meta)) return null;
  if (ld.length > SHARED_LIMITS.ldBlocks || meta.length > SHARED_LIMITS.metaTags) {
    return null;
  }
  if (!ld.every((b) => typeof b === 'string')) return null;
  if (ld.reduce((n: number, b: string) => n + b.length, 0) > SHARED_LIMITS.ldBytes) {
    return null;
  }
  const pairs: [string, string][] = [];
  for (const m of meta) {
    if (
      !Array.isArray(m) || m.length !== 2 ||
      typeof m[0] !== 'string' || typeof m[1] !== 'string' ||
      m[0].length > 100 || m[1].length > SHARED_LIMITS.metaValue
    ) {
      return null;
    }
    pairs.push([m[0], m[1]]);
  }
  return {
    title: title?.slice(0, SHARED_LIMITS.title),
    ld: ld as string[],
    meta: pairs,
  };
}

/** HTML mínimo com o que veio, para o parser de sempre. */
export function sharedPageHtml(page: SharedPage): string {
  const parts = ['<html><head>'];
  if (page.title != null) parts.push(`<title>${escapeHtml(page.title)}</title>`);
  for (const [key, value] of page.meta) {
    const k = escapeHtml(key);
    parts.push(`<meta property="${k}" name="${k}" content="${escapeHtml(value)}">`);
  }
  for (const block of page.ld) {
    // `</` não pode fechar o script antes do tempo; em JSON `<\/` é igual.
    parts.push(
      `<script type="application/ld+json">${block.replaceAll('</', '<\\/')}</script>`,
    );
  }
  parts.push('</head><body></body></html>');
  return parts.join('\n');
}

function escapeHtml(s: string): string {
  return s.replaceAll('&', '&amp;').replaceAll('"', '&quot;')
    .replaceAll('<', '&lt;').replaceAll('>', '&gt;');
}
