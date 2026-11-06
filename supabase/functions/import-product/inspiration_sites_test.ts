import { assertEquals } from '@std/assert';
import { inspirationSite } from './inspiration_sites.ts';

Deno.test('sites de inspiração', () => {
  for (
    const h of [
      'pinterest.com',
      'www.pinterest.com',
      'pt.pinterest.com',
      'pinterest.pt',
      'pinterest.co.uk',
      'pin.it',
    ]
  ) {
    assertEquals(inspirationSite(h)?.id, 'pinterest', h);
  }
  assertEquals(inspirationSite('www.instagram.com')?.id, 'instagram');
  for (
    const h of ['www.zara.com', 'notpinterest.com', 'pinterest.com.evil.example', 'pin.it.example']
  ) {
    assertEquals(inspirationSite(h), null, h);
  }
});
