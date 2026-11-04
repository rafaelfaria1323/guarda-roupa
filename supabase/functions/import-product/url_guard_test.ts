import { assertEquals } from '@std/assert';
import { checkImage, checkPage, storeOfImage } from './url_guard.ts';
import { STORES } from './stores.ts';

Deno.test('só https, domínios exatos da lista, sem credenciais nem porta', () => {
  const ok = checkPage('https://www.zara.com/pt/pt/x-p1.html#top');
  assertEquals(ok.ok && [ok.store.id, ok.url.hash], ['zara', '']);
  for (
    const [raw, reason] of [
      ['http://www.zara.com/x', 'invalid_url'],
      ['https://user:pw@www.zara.com/x', 'invalid_url'],
      ['https://www.zara.com:8443/x', 'invalid_url'],
      ['javascript:alert(1)', 'invalid_url'],
      ['não é um link', 'invalid_url'],
      ['https://zara.com.evil.example/x', 'unsupported_store'],
      ['https://evilzara.com/x', 'unsupported_store'],
      ['https://127.0.0.1/x', 'unsupported_store'],
      ['https://169.254.169.254/latest', 'unsupported_store'],
      ['https://www.mango.com/x', 'unsupported_store'],
    ]
  ) {
    const r = checkPage(raw);
    assertEquals(r.ok ? 'ok' : r.reason, reason, raw);
  }
});

Deno.test('imagens só dos domínios de imagens da própria loja', () => {
  const zara = STORES.find((s) => s.id === 'zara')!;
  assertEquals(
    checkImage('https://static.zara.net/a.jpg', zara)?.hostname,
    'static.zara.net',
  );
  assertEquals(checkImage('https://static.bershka.net/a.jpg', zara), null);
  assertEquals(checkImage('http://static.zara.net/a.jpg', zara), null);
  assertEquals(storeOfImage('https://image.uniqlo.com/t.jpg')?.id, 'uniqlo');
  assertEquals(storeOfImage('https://example.com/t.jpg'), null);
});
