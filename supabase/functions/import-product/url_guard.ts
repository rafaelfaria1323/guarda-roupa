/**
 * Regras de rede da função (docs/features/importacao-de-links.md). Aceita
 * qualquer site público, por isso o que se recusa é o que não é público:
 * IPs escritos à mão, nomes locais e, quando o runtime deixa resolver DNS,
 * nomes que apontam para redes privadas. Corre em cada redirecionamento.
 */

export type GuardResult =
  | { ok: true; url: URL }
  | { ok: false; reason: 'invalid_url' | 'not_public' };

/** Endereços de um nome; `null` se o runtime não deixar resolver. */
export type Resolver = (host: string) => Promise<string[] | null>;

/** Só https, sem credenciais nem porta, e um nome público (sem IPs). */
export function checkUrl(raw: string): GuardResult {
  if (typeof raw !== 'string' || raw.length > 2048) {
    return { ok: false, reason: 'invalid_url' };
  }
  let url: URL;
  try {
    url = new URL(raw.trim());
  } catch {
    return { ok: false, reason: 'invalid_url' };
  }
  if (url.protocol !== 'https:') return { ok: false, reason: 'invalid_url' };
  if (url.username !== '' || url.password !== '' || url.port !== '') {
    return { ok: false, reason: 'invalid_url' };
  }
  url.hash = '';
  if (!isPublicName(url.hostname)) return { ok: false, reason: 'not_public' };
  return { ok: true, url };
}

/** [checkUrl] e, se houver DNS, todos os endereços têm de ser públicos. */
export async function checkPublic(
  raw: string,
  resolve: Resolver = resolveDns,
): Promise<GuardResult> {
  const check = checkUrl(raw);
  if (!check.ok) return check;
  const addresses = await resolve(check.url.hostname);
  if (addresses != null && addresses.some((a) => !isPublicAddress(a))) {
    return { ok: false, reason: 'not_public' };
  }
  return check;
}

const LOCAL_SUFFIXES = [
  'localhost',
  'local',
  'internal',
  'intranet',
  'lan',
  'home',
  'corp',
  'home.arpa',
  'localdomain',
  'arpa',
];

/** Um nome com pelo menos um ponto, que não é IP nem nome local. */
export function isPublicName(host: string): boolean {
  const h = host.toLowerCase().replace(/\.$/, '');
  if (h.startsWith('[') || h.includes(':')) return false; // IPv6
  // IPv4 em qualquer forma (o URL já converte 0x7f.1 e 2130706433): nenhum
  // domínio de topo é só números.
  if (/^\d+$/.test(h.split('.').at(-1)!)) return false;
  if (!/^[a-z0-9.-]+$/.test(h) || !h.includes('.') || h.length > 253) {
    return false;
  }
  return !LOCAL_SUFFIXES.some((s) => h === s || h.endsWith(`.${s}`));
}

export function isPublicAddress(address: string): boolean {
  const a = address.toLowerCase();
  if (a.includes(':')) {
    const mapped = a.match(/^::ffff:(\d+\.\d+\.\d+\.\d+)$/);
    if (mapped) return isPublicAddress(mapped[1]);
    return !(a === '::' || a === '::1' || /^f[cd]/.test(a) || /^fe[89ab]/.test(a) ||
      a.startsWith('ff') || a.startsWith('64:ff9b:') || a.startsWith('2001:db8'));
  }
  const p = a.split('.').map(Number);
  if (p.length !== 4 || p.some((n) => !Number.isInteger(n) || n < 0 || n > 255)) {
    return false;
  }
  const [x, y] = p;
  return !(
    x === 0 || x === 10 || x === 127 || x >= 224 ||
    (x === 100 && y >= 64 && y <= 127) ||
    (x === 169 && y === 254) ||
    (x === 172 && y >= 16 && y <= 31) ||
    (x === 192 && y === 168) ||
    (x === 192 && y === 0 && p[2] === 0) ||
    (x === 198 && (y === 18 || y === 19))
  );
}

/** `Deno.resolveDns`, se o runtime o tiver; `null` se não. */
async function resolveDns(host: string): Promise<string[] | null> {
  // deno-lint-ignore no-explicit-any
  const resolve = (Deno as any).resolveDns as
    | ((h: string, t: 'A' | 'AAAA') => Promise<string[]>)
    | undefined;
  if (typeof resolve !== 'function') return null;
  const results = await Promise.allSettled([resolve(host, 'A'), resolve(host, 'AAAA')]);
  const ok = results.flatMap((r) => r.status === 'fulfilled' ? r.value : []);
  if (ok.length > 0) return ok;
  // Sem permissão ou sem suporte: fica a regra dos nomes. Nome que não
  // existe: o pedido falha sozinho.
  return null;
}
