import { assertEquals } from '@std/assert';
import { checkPublic, checkUrl, isPublicAddress } from './url_guard.ts';

Deno.test('qualquer site público em https; sem credenciais, porta nem IPs', () => {
  const ok = checkUrl('https://www.loja-nova.pt/p/1#top');
  assertEquals(ok.ok && [ok.url.hostname, ok.url.hash], ['www.loja-nova.pt', '']);
  for (
    const [raw, reason] of [
      ['http://www.zara.com/x', 'invalid_url'],
      ['https://user:pw@www.zara.com/x', 'invalid_url'],
      ['https://www.zara.com:8443/x', 'invalid_url'],
      ['javascript:alert(1)', 'invalid_url'],
      ['não é um link', 'invalid_url'],
      ['https://127.0.0.1/x', 'not_public'],
      ['https://169.254.169.254/latest', 'not_public'],
      ['https://2130706433/x', 'not_public'],
      ['https://0x7f.1/x', 'not_public'],
      ['https://[::1]/x', 'not_public'],
      ['https://localhost/x', 'not_public'],
      ['https://intranet/x', 'not_public'],
      ['https://db.internal/x', 'not_public'],
      ['https://router.home.arpa/x', 'not_public'],
      ['https://printer.local/x', 'not_public'],
    ]
  ) {
    const r = checkUrl(raw);
    assertEquals(r.ok ? 'ok' : r.reason, reason, raw);
  }
});

Deno.test('nomes que apontam para redes privadas são recusados', async () => {
  const dns = (map: Record<string, string[]>) => (h: string) => Promise.resolve(map[h] ?? null);
  const resolve = dns({
    'loja.example': ['93.184.216.34'],
    'rebind.example': ['93.184.216.34', '10.0.0.5'],
    'meta.example': ['169.254.169.254'],
    'v6.example': ['fd00::1'],
  });
  assertEquals((await checkPublic('https://loja.example/p', resolve)).ok, true);
  for (const host of ['rebind.example', 'meta.example', 'v6.example']) {
    const r = await checkPublic(`https://${host}/p`, resolve);
    assertEquals(r.ok ? 'ok' : r.reason, 'not_public', host);
  }
  // Sem DNS no runtime: ficam as regras dos nomes.
  assertEquals((await checkPublic('https://sem-dns.example/p', dns({}))).ok, true);
});

Deno.test('endereços públicos e privados', () => {
  for (const a of ['93.184.216.34', '8.8.8.8', '2606:4700::1111']) {
    assertEquals(isPublicAddress(a), true, a);
  }
  for (
    const a of [
      '10.1.2.3',
      '127.0.0.1',
      '172.16.0.1',
      '172.31.255.255',
      '192.168.1.1',
      '100.64.0.1',
      '169.254.169.254',
      '0.0.0.0',
      '224.0.0.1',
      '::1',
      'fe80::1',
      'fc00::1',
      '::ffff:10.0.0.1',
    ]
  ) {
    assertEquals(isPublicAddress(a), false, a);
  }
});
