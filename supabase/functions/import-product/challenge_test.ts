import { assertEquals } from '@std/assert';
import { isBotChallenge } from './challenge.ts';

const fixture = (name: string) =>
  Deno.readTextFileSync(new URL(`./fixtures/${name}`, import.meta.url));

Deno.test('desafios anti-bot conhecidos', () => {
  assertEquals(isBotChallenge(fixture('bot_challenge.html')), true);
  assertEquals(
    isBotChallenge('<html><head><title>Just a moment...</title></head></html>'),
    true,
  );
  assertEquals(
    isBotChallenge('<script>window._cf_chl_opt = {cType: "managed"};</script>'),
    true,
  );
  assertEquals(
    isBotChallenge('<script src="https://geo.captcha-delivery.com/c.js"></script>'),
    true,
  );
});

Deno.test('páginas normais não são desafios', () => {
  assertEquals(isBotChallenge(fixture('none.html')), false);
  assertEquals(isBotChallenge(fixture('microdata.html')), false);
  assertEquals(isBotChallenge('<p>verify your bm account</p>'), false);
});
