/**
 * A página é um desafio anti-bot (a loja quer correr JavaScript antes de
 * mostrar o produto)? Só se pergunta quando a página não tem produto:
 * algumas páginas normais trazem scripts destes serviços.
 *
 * Não se resolve o desafio (P-12: não contornar anti-bot). Serve para dizer
 * a verdade ao utilizador, "a loja bloqueia leituras automáticas", em vez de
 * "a página não tem dados".
 */
export function isBotChallenge(html: string): boolean {
  const head = html.slice(0, 64 * 1024);
  return MARKERS.some((m) => m.test(head));
}

const MARKERS: readonly RegExp[] = [
  // Akamai Bot Manager (Inditex: Zara, Massimo Dutti, …).
  /[?&"]bm-verify[="]/,
  /\/_sec\/verify\?provider=interstitial/,
  // Cloudflare.
  /window\._cf_chl_opt\b/,
  /<title>\s*Just a moment\.\.\.\s*<\/title>/i,
  // DataDome.
  /captcha-delivery\.com/,
  // PerimeterX / HUMAN.
  /px-captcha/,
];
