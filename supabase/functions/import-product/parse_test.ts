import { assertEquals } from '@std/assert';
import { parseProduct } from './parse.ts';

const page = new URL('https://www.zara.com/pt/pt/camisa-p1.html');
const fixture = (name: string) =>
  Deno.readTextFileSync(new URL(`./fixtures/${name}`, import.meta.url));

Deno.test('ProductGroup: campos, variantes e imagens absolutas https', () => {
  const p = parseProduct(fixture('product_group.html'), page)!;
  assertEquals(p.name, 'Camisa de linho & algodão');
  assertEquals(p.brand, 'Loja');
  assertEquals(p.description, 'Camisa leve. Lavar a 30 °C');
  assertEquals(p.material, 'Linho');
  assertEquals(p.images, [
    'https://static.zara.net/a.jpg',
    'https://www.zara.com/b.jpg',
  ]);
  assertEquals(p.variants, [
    {
      color: 'Branco',
      size: 'M',
      sku: '1-M',
      image: 'https://static.zara.net/branco.jpg',
    },
    {
      color: 'Azul',
      size: 'M',
      sku: '2-M',
      image: 'https://static.zara.net/azul.jpg',
    },
  ]);
  assertEquals(p.sources.name, 'json-ld');
  assertEquals(p.confirm, ['category', 'colors', 'owned', 'variant']);
});

Deno.test('@graph e JSON inválido ao lado', () => {
  const p = parseProduct(fixture('product_graph.html'), page)!;
  assertEquals([p.name, p.brand, p.color], ['T-shirt', 'Marca', 'Preto']);
  assertEquals(p.confirm, ['category', 'colors', 'owned', 'material']);
});

Deno.test('só Open Graph: alternativa parcial, origem dita', () => {
  const p = parseProduct(fixture('og_only.html'), page)!;
  assertEquals(p.name, 'Calças largas');
  assertEquals(p.description, 'Ganga é confortável');
  assertEquals(p.brand, 'Bershka');
  assertEquals(p.images.length, 2);
  assertEquals(p.sources, {
    name: 'open-graph',
    brand: 'open-graph',
    description: 'open-graph',
    images: 'open-graph',
  });
  assertEquals(p.variants, []);
});

Deno.test('sem metadados: null, não um produto inventado', () => {
  assertEquals(parseProduct(fixture('none.html'), page), null);
});

Deno.test('textos longos cortados e sem caracteres de controlo', () => {
  const html = `<script type="application/ld+json">${
    JSON.stringify({ '@type': 'Product', name: `a\u0000b${'x'.repeat(500)}` })
  }</script>`;
  const p = parseProduct(html, page)!;
  assertEquals(p.name!.length, 200);
  assertEquals(p.name!.startsWith('a b'), true);
});

Deno.test('microdata schema.org: qualquer site, com a origem dita', () => {
  const p = parseProduct(fixture('microdata.html'), new URL('https://www.loja-nova.pt/p/1'))!;
  assertEquals(p.name, 'Casaco de lã & caxemira');
  assertEquals(p.brand, 'Loja Nova');
  assertEquals(p.color, 'Camel');
  assertEquals(p.material, '80% lã, 20% caxemira');
  assertEquals(p.images, ['https://www.loja-nova.pt/img/casaco.jpg']);
  assertEquals(p.sources.name, 'microdata');
  assertEquals(p.confirm, ['category', 'colors', 'owned']);
});

Deno.test('Twitter cards e HTML simples: o nome é o título e pede confirmação', () => {
  const p = parseProduct(fixture('twitter_html.html'), page)!;
  assertEquals(p.name, 'Sapatilhas brancas — Sapataria');
  assertEquals(p.description, 'Sapatilhas em pele.');
  assertEquals(p.images, [
    'https://cdn.sapataria.example/s.jpg',
    'https://cdn.sapataria.example/s2.jpg',
  ]);
  assertEquals(p.sources, {
    name: 'html',
    description: 'html',
    images: 'open-graph',
  });
  assertEquals(p.confirm.includes('name'), true);
});

Deno.test('só um título, sem imagem nem dados: não é um produto', () => {
  assertEquals(parseProduct(fixture('title_only.html'), page), null);
});
