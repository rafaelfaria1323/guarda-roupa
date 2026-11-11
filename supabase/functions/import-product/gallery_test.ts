import { assertEquals } from '@std/assert';
import { readGallery, withGallery } from './gallery.ts';

const z = 'https://static.zara.net/assets/public/ab12/04749700800-p/04749700800-p.jpg?ts=1&w=750';

Deno.test('galeria: só endereços https, sem repetidos e com limite', () => {
  assertEquals(readGallery('x'), []);
  assertEquals(
    readGallery(['https://a.com/1.jpg', 'http://a.com/2.jpg', 'https://a.com/1.jpg', 42, 'nada']),
    ['https://a.com/1.jpg'],
  );
  const many = Array.from({ length: 80 }, (_, i) => `https://a.com/${i}.jpg`);
  assertEquals(readGallery(many).length, 60);
  assertEquals(readGallery(['https://a.com/' + 'x'.repeat(3000)]), []);
});

Deno.test('galeria: junta as fotos com a referência do produto (Zara)', () => {
  const gallery = [
    'https://static.zara.net/assets/public/ab12/04749700800-p/04749700800-p.jpg?ts=1&w=1024',
    'https://static.zara.net/assets/public/cd34/04749700800-a1/04749700800-a1.jpg?ts=1&w=1024',
    'https://static.zara.net/assets/public/ef56/04749700800-e1/04749700800-e1.jpg?ts=1&w=1024',
    // Outra peça (recomendações) e o logótipo ficam de fora.
    'https://static.zara.net/assets/public/9999/05555500800-p/05555500800-p.jpg?w=400',
    'https://static.zara.net/photos/logo.png',
    'https://static.zara.net/assets/chip/04749700800-chip.jpg',
    'https://outro.cdn.com/04749700800-a2.jpg',
  ];
  assertEquals(withGallery([z], gallery), [
    z,
    'https://static.zara.net/assets/public/cd34/04749700800-a1/04749700800-a1.jpg?ts=1&w=1024',
    'https://static.zara.net/assets/public/ef56/04749700800-e1/04749700800-e1.jpg?ts=1&w=1024',
  ]);
});

Deno.test('galeria: sem referência, as da mesma pasta', () => {
  const main = 'https://cdn.loja.pt/produtos/casaco-azul/frente.jpg';
  assertEquals(
    withGallery([main], [
      'https://cdn.loja.pt/produtos/casaco-azul/costas.jpg',
      'https://cdn.loja.pt/produtos/casaco-azul/icone.svg',
      'https://cdn.loja.pt/produtos/calcas/frente.jpg',
    ]),
    [main, 'https://cdn.loja.pt/produtos/casaco-azul/costas.jpg'],
  );
});

Deno.test('galeria: sem foto principal não junta nada; no máximo 12', () => {
  assertEquals(withGallery([], ['https://a.com/1.jpg']), []);
  const gallery = Array.from(
    { length: 20 },
    (_, i) => `https://static.zara.net/a/${i}/04749700800-a${i}.jpg`,
  );
  assertEquals(withGallery([z], gallery).length, 12);
});

Deno.test('galeria: a referência vem do link da página (Gant, com marcas de tempo)', () => {
  const page = new URL('https://www.gant.pt/p/t-shirt-archive-shield-white/2003199-110');
  const base = 'https://www.gant.pt/on/demandware.static/-/Sites-gant-master/default';
  const dis =
    'https://www.gant.pt/dw/image/v2/BFLN_PRD/on/demandware.static/-/Sites-gant-master/default';
  const main = `${base}/dw8b/PhotoStudio/time__1786370443__202603-2003199-110-model-fv-1.jpg`;
  const gallery = [
    // A mesma foto noutro endereço conta uma vez.
    `${dis}/dw8b/PhotoStudio/time__1786370443__202603-2003199-110-model-fv-1.jpg?sw=1228`,
    `${dis}/dw5d/PhotoStudio/time__1786370445__202603-2003199-110-look-fv-1.jpg?sw=1228`,
    `${dis}/dwf0/PhotoStudio/time__1786370446__202603-2003199-110-crmodel-fv-1.jpg?sw=1228`,
    `${dis}/dw2f/PhotoStudio/time__1786370444__202603-2003199-110-model-bv-1.jpg?sw=1228`,
    `${dis}/dw99/PhotoStudio/time__1786370999__202603-2009999-110-model-fv-1.jpg?sw=1228`,
    'https://cdn.cookielaw.org/logos/static/ot_company_logo.png',
  ];
  const got = withGallery([main], gallery, page);
  assertEquals(got.length, 4);
  assertEquals(got.some((u) => u.includes('2009999')), false);
});

Deno.test('galeria: a referência da Zara no link apanha as fotos de todas as vistas', () => {
  const page = new URL('https://www.zara.com/pt/pt/casaco-polipele-botoes-p04749700.html');
  const got = withGallery([z], [
    'https://static.zara.net/assets/public/cd34/04749700800-a1/04749700800-a1.jpg?w=1024',
    'https://static.zara.net/assets/public/9999/05555500800-p/05555500800-p.jpg?w=400',
  ], page);
  assertEquals(got.length, 2);
});
