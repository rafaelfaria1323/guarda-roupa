import { fetchImage, fetchPage } from './fetch_limited.ts';
import { parseProduct, type Source } from './parse.ts';
import { siteName } from './stores.ts';
import { checkPublic, type Resolver } from './url_guard.ts';

/** `ok`, ou porque não se pode usar agora. */
export type Quota = 'ok' | 'forbidden' | 'rate_limited' | 'unauthorized';

/** Estado do site, a partir do perfil que a base atualiza sozinha. */
export type SiteStatus = 'new' | 'testing' | 'works' | 'failing';

export interface Recorded {
  status: SiteStatus;
  ok_count: number;
  fail_count: number;
}

export interface Deps {
  /** Conta o pedido (`claim_import_quota`) como o utilizador do token. */
  claimQuota: (authorization: string, apiKey: string | null) => Promise<Quota>;
  /**
   * Atualiza o perfil do domínio e autoriza as imagens oferecidas
   * (`record_import`). `null` se não deu: a pré-visualização segue na mesma.
   */
  record: (
    authorization: string,
    apiKey: string | null,
    entry: { host: string; result: string; source?: Source; images: string[] },
  ) => Promise<Recorded | null>;
  /** A imagem foi oferecida a este utilizador (`import_image_allowed`)? */
  imageAllowed: (
    authorization: string,
    apiKey: string | null,
    url: string,
  ) => Promise<boolean>;
  fetchFn?: (input: URL, init: RequestInit) => Promise<Response>;
  resolve?: Resolver;
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
 * POST `{url}`: pré-visualização do produto de qualquer site público.
 * POST `{image}`: copia uma imagem que esta função ofereceu ao utilizador
 * numa pré-visualização recente (para a peça ficar com o ficheiro). Sempre
 * autenticado, na allowlist (P-16) e com quota; nunca um proxy de URLs
 * arbitrários nem de redes internas.
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
  const apiKey = req.headers.get('apikey');

  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return json({ result: 'error', reason: 'invalid_request' }, 400);
  }
  const fields = typeof body === 'object' && body != null ? body as Record<string, unknown> : {};
  const page = fields.url;
  const image = fields.image;
  if (typeof page !== 'string' && typeof image !== 'string') {
    return json({ result: 'error', reason: 'invalid_request' }, 400);
  }

  // Validar antes de gastar quota: um link inválido ou interno não conta.
  const raw = (typeof page === 'string' ? page : image) as string;
  const check = await checkPublic(raw, deps.resolve);
  if (!check.ok) return json({ result: check.reason });

  const quota = await deps.claimQuota(authorization, apiKey);
  if (quota === 'unauthorized') {
    return json({ result: 'error', reason: quota }, 401);
  }
  if (quota === 'forbidden') {
    return json({ result: 'error', reason: quota }, 403);
  }
  if (quota === 'rate_limited') return json({ result: 'rate_limited' }, 429);

  if (typeof image === 'string') {
    if (!await deps.imageAllowed(authorization, apiKey, check.url.href)) {
      return json({ result: 'image_not_offered' }, 403);
    }
    const got = await fetchImage(check.url, deps.fetchFn, deps.resolve);
    if (!got.ok) {
      return json({ result: 'fetch_failed', reason: got.reason, status: got.status });
    }
    return new Response(got.body as Uint8Array<ArrayBuffer>, {
      headers: {
        ...CORS,
        'content-type': got.contentType,
        'cache-control': 'no-store',
      },
    });
  }

  const got = await fetchPage(check.url, deps.fetchFn, deps.resolve);
  const host = (got.ok ? got.url : check.url).hostname;
  const site = async (
    result: string,
    source?: Source,
    images: string[] = [],
  ) => {
    let recorded: Recorded | null = null;
    try {
      recorded = await deps.record(authorization, apiKey, { host, result, source, images });
    } catch {
      // O perfil é uma ajuda: sem ele a importação continua.
    }
    return {
      id: host,
      name: siteName(host),
      status: recorded?.status ?? 'new',
      okCount: recorded?.ok_count ?? 0,
    };
  };

  if (!got.ok) {
    return json({
      result: 'fetch_failed',
      reason: got.reason,
      status: got.status,
      store: await site('fetch_failed'),
    });
  }
  const html = new TextDecoder().decode(got.body);
  const product = parseProduct(html, got.url);
  if (product == null) {
    return json({
      result: 'no_metadata',
      store: await site('no_metadata'),
      url: got.url.href,
    });
  }
  const offered = [
    ...product.images,
    ...product.variants.flatMap((v) => v.image == null ? [] : [v.image]),
  ].filter((u, i, all) => all.indexOf(u) === i).slice(0, 12);
  return json({
    result: 'ok',
    store: await site('ok', product.sources.name ?? product.sources.images, offered),
    url: got.url.href,
    product,
  });
}
