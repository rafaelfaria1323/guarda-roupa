import { checkImage, checkPage } from './url_guard.ts';
import type { Store } from './stores.ts';

export const LIMITS = {
  timeoutMs: 8000,
  maxRedirects: 3,
  maxPageBytes: 2 * 1024 * 1024,
  maxImageBytes: 5 * 1024 * 1024,
};

export type FetchFailure =
  | 'timeout'
  | 'too_large'
  | 'redirect_not_allowed'
  | 'too_many_redirects'
  | 'not_html'
  | 'not_image'
  | 'blocked'
  | 'not_found'
  | 'http_error'
  | 'network';

export type Fetched =
  | { ok: true; url: URL; body: Uint8Array; contentType: string }
  | { ok: false; reason: FetchFailure; status?: number };

type FetchFn = (input: URL, init: RequestInit) => Promise<Response>;

/**
 * Pede uma página de produto. Redirecionamentos seguidos à mão, cada um
 * validado de novo (o destino tem de ser a mesma loja). Tempo e bytes
 * limitados. Sem cookies nem credenciais: não se contorna login nem
 * anti-bot, e um bloqueio é dito como tal.
 */
export function fetchPage(
  url: URL,
  store: Store,
  fetchFn: FetchFn = fetch,
): Promise<Fetched> {
  return fetchLimited(url, {
    fetchFn,
    maxBytes: LIMITS.maxPageBytes,
    accept: 'text/html,application/xhtml+xml',
    allowed: (next) => {
      const check = checkPage(next.href);
      return check.ok && check.store.id === store.id ? check.url : null;
    },
    typeOk: (t) => t.includes('html'),
    wrongType: 'not_html',
  });
}

/** Copia uma imagem de um domínio de imagens da loja. */
export function fetchImage(
  url: URL,
  store: Store,
  fetchFn: FetchFn = fetch,
): Promise<Fetched> {
  return fetchLimited(url, {
    fetchFn,
    maxBytes: LIMITS.maxImageBytes,
    accept: 'image/jpeg,image/png,image/webp',
    allowed: (next) => checkImage(next.href, store),
    typeOk: (t) => /^image\/(jpeg|png|webp)/.test(t),
    wrongType: 'not_image',
  });
}

async function fetchLimited(
  start: URL,
  o: {
    fetchFn: FetchFn;
    maxBytes: number;
    accept: string;
    allowed: (url: URL) => URL | null;
    typeOk: (contentType: string) => boolean;
    wrongType: FetchFailure;
  },
): Promise<Fetched> {
  const signal = AbortSignal.timeout(LIMITS.timeoutMs);
  let url = start;
  try {
    for (let hop = 0;; hop++) {
      const res = await o.fetchFn(url, {
        redirect: 'manual',
        signal,
        headers: {
          'accept': o.accept,
          'accept-language': 'pt-PT,pt;q=0.9,en;q=0.5',
          'user-agent': 'GuardaRoupa/1.0 (importação pessoal de produto)',
        },
      });
      if (res.status >= 300 && res.status < 400) {
        await res.body?.cancel();
        if (hop >= LIMITS.maxRedirects) {
          return { ok: false, reason: 'too_many_redirects' };
        }
        const location = res.headers.get('location');
        const next = location == null ? null : safeUrl(location, url);
        const allowed = next == null ? null : o.allowed(next);
        if (allowed == null) {
          return { ok: false, reason: 'redirect_not_allowed' };
        }
        url = allowed;
        continue;
      }
      if (!res.ok) {
        await res.body?.cancel();
        const reason = res.status === 404 || res.status === 410
          ? 'not_found'
          : res.status === 401 || res.status === 403 || res.status === 429
          ? 'blocked'
          : 'http_error';
        return { ok: false, reason, status: res.status };
      }
      const contentType = (res.headers.get('content-type') ?? '').toLowerCase();
      if (!o.typeOk(contentType)) {
        await res.body?.cancel();
        return { ok: false, reason: o.wrongType };
      }
      const declared = Number(res.headers.get('content-length') ?? '0');
      if (declared > o.maxBytes) {
        await res.body?.cancel();
        return { ok: false, reason: 'too_large' };
      }
      const body = await readLimited(res, o.maxBytes);
      if (body == null) return { ok: false, reason: 'too_large' };
      return { ok: true, url, body, contentType };
    }
  } catch (e) {
    if (e instanceof DOMException && e.name === 'TimeoutError') {
      return { ok: false, reason: 'timeout' };
    }
    return { ok: false, reason: 'network' };
  }
}

function safeUrl(location: string, base: URL): URL | null {
  try {
    return new URL(location, base);
  } catch {
    return null;
  }
}

async function readLimited(
  res: Response,
  maxBytes: number,
): Promise<Uint8Array | null> {
  if (res.body == null) return new Uint8Array();
  const reader = res.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.byteLength;
    if (total > maxBytes) {
      await reader.cancel();
      return null;
    }
    chunks.push(value);
  }
  const out = new Uint8Array(total);
  let offset = 0;
  for (const c of chunks) {
    out.set(c, offset);
    offset += c.byteLength;
  }
  return out;
}
