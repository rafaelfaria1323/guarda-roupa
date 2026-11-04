// Smoke local (sem conta nem quota): `deno run --allow-net cli.ts <link>`.
// Mostra o que a função extrairia desta página. Ver tool/import/README.md.
import { fetchPage } from './fetch_limited.ts';
import { parseProduct } from './parse.ts';
import { siteName } from './stores.ts';
import { checkPublic } from './url_guard.ts';

const link = Deno.args[0];
if (link == null) {
  console.error('Uso: deno run --allow-net cli.ts <link de produto>');
  Deno.exit(2);
}
const check = await checkPublic(link);
if (!check.ok) {
  console.log(JSON.stringify({ result: check.reason }, null, 2));
  Deno.exit(1);
}
const got = await fetchPage(check.url);
if (!got.ok) {
  console.log(JSON.stringify({ result: 'fetch_failed', ...got }, null, 2));
  Deno.exit(1);
}
const product = parseProduct(new TextDecoder().decode(got.body), got.url);
console.log(JSON.stringify(
  product == null ? { result: 'no_metadata', url: got.url.href } : {
    result: 'ok',
    site: siteName(got.url.hostname),
    url: got.url.href,
    product,
  },
  null,
  2,
));
