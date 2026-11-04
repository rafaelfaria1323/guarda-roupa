import { fetchImage, fetchPage } from './fetch_limited.ts';
import { parseProduct } from './parse.ts';
import { checkImage, checkPage, storeOfImage } from './url_guard.ts';

/** `ok`, ou porque não se pode usar agora. */
export type Quota = 'ok' | 'forbidden' | 'rate_limited' | 'unauthorized';

export interface Deps {
  /** Conta o pedido (`claim_import_quota`) como o utilizador do token. */
  claimQuota: (authorization: string, apiKey: string | null) => Promise<Quota>;
  fetchFn?: (input: URL, init: RequestInit) => Promise<Response>;
}

const CORS = {
  'access-control-allow-origin': '*',
  'access-control-allow-headers': 'authorization, apikey, content-type, x-client-info',
  'access-control-allow-methods': 'POST, OPTIONS',
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, 'content-type': 'application/json; charset=utf-8' },
  });
}

/**
 * POST `{url}`: pré-visualização do produto. POST `{image}`: copia uma
 * imagem de um domínio de imagens de uma loja da lista (para a peça ficar
 * com o ficheiro, não com um link temporário). Sempre autenticado, na
 * allowlist (P-16) e com quota; nunca um proxy de URLs arbitrários.
 */
export async function handle(req: Request, deps: Deps): Promise<Response> {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS });
  if (req.method !== 'POST') {
    return json({ result: 'error', reason: 'method' }, 405);
  }

  const authorization = req.headers.get('authorization') ?? '';
  if (!authorization.toLowerCase().startsWith('bearer ')) {
    return json({ result: 'error', reason: 'unauthorized' }, 401);
  }

  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return json({ result: 'error', reason: 'invalid_request' }, 400);
  }
  const page = typeof body === 'object' && body != null
    ? (body as Record<string, unknown>).url
    : undefined;
  const image = typeof body === 'object' && body != null
    ? (body as Record<string, unknown>).image
    : undefined;
  if (typeof page !== 'string' && typeof image !== 'string') {
    return json({ result: 'error', reason: 'invalid_request' }, 400);
  }

  // Validar antes de gastar quota: um link de outra loja não conta.
  let target: { url: URL; store: import('./stores.ts').Store };
  if (typeof page === 'string') {
    const check = checkPage(page);
    if (!check.ok) return json({ result: check.reason });
    target = check;
  } else {
    const store = storeOfImage(image as string);
    const url = store == null ? null : checkImage(image as string, store);
    if (store == null || url == null) {
      return json({ result: 'unsupported_store' });
    }
    target = { url, store };
  }

  const quota = await deps.claimQuota(authorization, req.headers.get('apikey'));
  if (quota === 'unauthorized') {
    return json({ result: 'error', reason: quota }, 401);
  }
  if (quota === 'forbidden') {
    return json({ result: 'error', reason: quota }, 403);
  }
  if (quota === 'rate_limited') return json({ result: 'rate_limited' }, 429);

  const store = {
    id: target.store.id,
    name: target.store.name,
    status: target.store.status,
  };
  if (typeof image === 'string') {
    const got = await fetchImage(target.url, target.store, deps.fetchFn);
    if (!got.ok) {
      return json({
        result: 'fetch_failed',
        reason: got.reason,
        status: got.status,
      });
    }
    return new Response(got.body as Uint8Array<ArrayBuffer>, {
      headers: {
        ...CORS,
        'content-type': got.contentType,
        'cache-control': 'no-store',
      },
    });
  }

  const got = await fetchPage(target.url, target.store, deps.fetchFn);
  if (!got.ok) {
    return json({
      result: 'fetch_failed',
      reason: got.reason,
      status: got.status,
      store,
    });
  }
  const html = new TextDecoder().decode(got.body);
  const product = parseProduct(html, got.url);
  if (product == null) {
    return json({ result: 'no_metadata', store, url: got.url.href });
  }
  return json({
    result: 'ok',
    store,
    url: got.url.href,
    product: {
      ...product,
      // Só se oferecem imagens que a função consegue copiar.
      images: product.images.filter((i) => checkImage(i, target.store) != null),
      otherImages: product.images.filter((i) => checkImage(i, target.store) == null).length,
    },
  });
}
