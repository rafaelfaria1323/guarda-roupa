import { type Store, STORES } from './stores.ts';

export type GuardResult =
  | { ok: true; url: URL; store: Store }
  | { ok: false; reason: 'invalid_url' | 'unsupported_store' };

/**
 * Só https, sem credenciais nem porta, e só domínios exatos da lista. Não
 * há IPs nem redes internas possíveis: nenhum domínio da lista é interno.
 * Corre também em cada redirecionamento.
 */
export function checkPage(raw: string, stores = STORES): GuardResult {
  const url = parse(raw);
  if (url == null) return { ok: false, reason: 'invalid_url' };
  const store = stores.find((s) => s.hosts.includes(url.hostname));
  if (store == null) return { ok: false, reason: 'unsupported_store' };
  return { ok: true, url, store };
}

/** Uma imagem só de um domínio de imagens de [store]. */
export function checkImage(raw: string, store: Store): URL | null {
  const url = parse(raw);
  return url != null && store.imageHosts.includes(url.hostname) ? url : null;
}

/** A loja a que pertence um domínio de imagens. */
export function storeOfImage(raw: string, stores = STORES): Store | null {
  const url = parse(raw);
  if (url == null) return null;
  return stores.find((s) => s.imageHosts.includes(url.hostname)) ?? null;
}

function parse(raw: string): URL | null {
  if (typeof raw !== 'string' || raw.length > 2048) return null;
  let url: URL;
  try {
    url = new URL(raw.trim());
  } catch {
    return null;
  }
  if (url.protocol !== 'https:') return null;
  if (url.username !== '' || url.password !== '') return null;
  if (url.port !== '') return null;
  url.hash = '';
  return url;
}
