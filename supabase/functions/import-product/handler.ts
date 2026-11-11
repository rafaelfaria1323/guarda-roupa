import { isBotChallenge } from './challenge.ts';
import { fetchImage, fetchPage } from './fetch_limited.ts';
import { parseProduct, type ProductPreview, type Source } from './parse.ts';
import { readSharedPage, type SharedPage, sharedPageHtml } from './shared_page.ts';
import {
  inspirationSite,
  readImageWhy,
  readInspiration,
  readSharedImage,
} from './inspiration_sites.ts';
import { siteName } from './stores.ts';
import { checkPublic, type Resolver } from './url_guard.ts';

/** `ok`, ou porque não se pode usar agora. */
export type Quota = 'ok' | 'forbidden' | 'rate_limited' | 'unauthorized';

/** Resposta de `submit_import_inbox`. */
export type InboxResult = 'ok' | 'invalid_key' | 'forbidden' | 'rate_limited' | 'full';

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
  /**
   * Entrega na caixa "Por importar" do dono da chave (`submit_import_inbox`),
   * como anónimo: a chave do atalho é a autenticação.
   */
  submitInbox?: (
    key: string,
    apiKey: string | null,
    entry: { url: string; preview: unknown; images: string[] },
  ) => Promise<InboxResult>;
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

  const inboxKey = req.headers.get('x-fio-key');
  if (inboxKey != null) return await toInbox(req, inboxKey, deps);

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

  // Página partilhada pelo atalho: só com o link da página.
  let shared: SharedPage | null = null;
  if (fields.page !== undefined) {
    shared = typeof page === 'string' ? readSharedPage(fields.page) : null;
    if (shared == null) return json({ result: 'error', reason: 'invalid_request' }, 400);
  }

  // Validar antes de gastar quota: um link inválido ou interno não conta.
  const raw = (typeof page === 'string' ? page : image) as string;
  const check = await checkPublic(raw, deps.resolve);
  if (!check.ok) return json({ result: check.reason });
  // Pinterest e Instagram não se leem (robots.txt) e não são peças: são
  // inspirações, que só entram pelo atalho. Não gasta quota.
  const inspiration = typeof page === 'string' ? inspirationSite(check.url.hostname) : null;
  if (inspiration != null) {
    return json({ result: 'inspiration_site', site: inspiration.name });
  }

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

  if (shared != null) return await fromShared(authorization, apiKey, check.url, shared, deps);

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
  if (product == null && isBotChallenge(html)) {
    // Desafio anti-bot (ex.: Akamai na Zara): é um bloqueio, não uma página
    // sem dados. Não se contorna.
    return json({
      result: 'fetch_failed',
      reason: 'blocked',
      status: 200,
      store: await site('fetch_failed'),
    });
  }
  if (product == null) {
    return json({
      result: 'no_metadata',
      store: await site('no_metadata'),
      url: got.url.href,
    });
  }
  const offered = offeredImages(product);
  return json({
    result: 'ok',
    store: await site('ok', product.sources.name ?? product.sources.images, offered),
    url: got.url.href,
    product,
  });
}

function offeredImages(product: ProductPreview): string[] {
  return [
    ...product.images,
    ...product.variants.flatMap((v) => v.image == null ? [] : [v.image]),
  ].filter((u, i, all) => all.indexOf(u) === i).slice(0, 12);
}

/**
 * A página que o utilizador abriu no Safari e partilhou (atalho do iPhone).
 * Não se pede nada à loja. `record_import` com `shared` só autoriza as
 * imagens: não conta para o estado do site, que diz se o link funciona.
 */
async function fromShared(
  authorization: string,
  apiKey: string | null,
  url: URL,
  page: SharedPage,
  deps: Deps,
): Promise<Response> {
  const product = parseProduct(sharedPageHtml(page), url);
  const images = product == null ? [] : offeredImages(product);
  let recorded: Recorded | null = null;
  try {
    recorded = await deps.record(authorization, apiKey, {
      host: url.hostname,
      result: 'shared',
      source: product?.sources.name ?? product?.sources.images,
      images,
    });
  } catch {
    // Sem registo, as imagens não se copiam, mas os dados aparecem.
  }
  const store = {
    id: url.hostname,
    name: siteName(url.hostname),
    status: recorded?.status ?? 'new',
    okCount: recorded?.ok_count ?? 0,
  };
  if (product == null) return json({ result: 'no_metadata', store, url: url.href });
  return json({ result: 'ok', store, url: url.href, product, via: 'shared' });
}

/** Resposta para a notificação do atalho: texto simples, em português. */
function say(text: string, status = 200): Response {
  return new Response(text, {
    status,
    headers: { 'content-type': 'text/plain; charset=utf-8', 'cache-control': 'no-store' },
  });
}

/**
 * O atalho do iPhone manda a página aberta no Safari, com a chave pessoal
 * no cabeçalho `x-fio-key` (sem sessão). A pré-visualização fica na caixa
 * "Por importar" do dono; a app trata do resto. A `apikey` pública do
 * projeto pode vir no link (`?apikey=`), porque o atalho não tem outra.
 */
async function toInbox(req: Request, key: string, deps: Deps): Promise<Response> {
  if (req.method !== 'POST') return say('Usa o atalho a partir do Safari.', 405);
  const send = deps.submitInbox;
  if (send == null) return say('O fio não está disponível agora.', 503);
  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return say('O atalho não mandou a página. Corre-o a partir do Safari.', 400);
  }
  const fields = typeof body === 'object' && body != null ? body as Record<string, unknown> : {};
  const page = readSharedPage(fields);
  if (fields.fio !== 1 || typeof fields.url !== 'string' || page == null) {
    return say('O atalho não mandou a página. Confirma o script no atalho.', 400);
  }
  const check = await checkPublic(fields.url, deps.resolve);
  if (!check.ok) return say('Este link não se pode importar.', 400);

  const apiKey = req.headers.get('apikey') ?? new URL(req.url).searchParams.get('apikey');
  const site = inspirationSite(check.url.hostname);
  if (site != null) {
    const found = readInspiration(page, check.url, site);
    // A imagem do Pin, se o Safari do utilizador a leu na página.
    const image = readSharedImage(fields.image);
    const preview = {
      result: 'ok',
      kind: 'inspiration',
      site: site.name,
      url: found.url,
      inspiration: {
        title: found.title,
        description: found.description,
        ...(image == null ? {} : { image }),
      },
      via: 'shared',
    };
    const name = found.title ?? site.name;
    let sent = `Inspiração enviada para o fio: ${name}.`;
    if (site.id === 'pinterest') {
      // Diz se a imagem veio, para se perceber logo quando o Safari não a leu.
      const why = readImageWhy(fields.imageWhy);
      sent = image != null
        ? `Inspiração enviada para o fio, com a imagem: ${name}.`
        : `${sent} A imagem do Pin não veio${why == null ? '' : ` (${why})`}.`;
    }
    return await submit(send, key, apiKey, { url: found.url, preview, images: [] }, sent);
  }

  const product = parseProduct(sharedPageHtml(page), check.url);
  if (product == null) {
    return say('A página não tem os dados do produto. Abre a página de uma peça.', 422);
  }
  const preview = {
    result: 'ok',
    store: {
      id: check.url.hostname,
      name: siteName(check.url.hostname),
      status: 'new',
      okCount: 0,
    },
    url: check.url.href,
    product,
    via: 'shared',
  };
  return await submit(
    send,
    key,
    apiKey,
    { url: check.url.href, preview, images: offeredImages(product) },
    `Enviada para o fio: ${product.name ?? siteName(check.url.hostname)}.`,
  );
}

/** Entrega na caixa e diz o resultado em texto, para a notificação. */
async function submit(
  send: NonNullable<Deps['submitInbox']>,
  key: string,
  apiKey: string | null,
  entry: { url: string; preview: unknown; images: string[] },
  sent: string,
): Promise<Response> {
  let result: InboxResult;
  try {
    result = await send(key, apiKey, entry);
  } catch {
    return say('O fio não está disponível agora. Tenta daqui a pouco.', 503);
  }
  switch (result) {
    case 'ok':
      return say(sent);
    case 'invalid_key':
      return say('A chave do atalho não é válida. Cria uma nova no fio.', 401);
    case 'forbidden':
      return say('Esta conta não tem acesso ao fio.', 403);
    case 'rate_limited':
      return say('Muitas importações seguidas. Tenta mais tarde.', 429);
    case 'full':
      return say('Já tens 20 envios por tratar. Abre o fio primeiro.', 409);
  }
}
