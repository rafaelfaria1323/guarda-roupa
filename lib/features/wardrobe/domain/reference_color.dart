/// Cores de referência para o utilizador escolher. Guarda-se só o RGB
/// (`GarmentColor.rgb`); o nome é da apresentação. Um RGB fora desta lista
/// (ex.: sugerido por análise de imagem no futuro) continua válido.
enum ReferenceColor {
  white('white', 0xFFFFFF),
  cream('cream', 0xF3EBD9),
  beige('beige', 0xD6C2A1),
  khaki('khaki', 0xB9A77A),
  brown('brown', 0x6D4C41),
  grey('grey', 0x9E9E9E),
  charcoal('charcoal', 0x45474B),
  black('black', 0x141414),
  navy('navy', 0x1F2A44),
  blue('blue', 0x2F6DB5),
  lightBlue('light_blue', 0xA7C7E7),
  denim('denim', 0x4A6A8A),
  green('green', 0x2E7D32),
  olive('olive', 0x6B6B2A),
  yellow('yellow', 0xF2C94C),
  orange('orange', 0xE67E22),
  red('red', 0xC0392B),
  burgundy('burgundy', 0x6D1A36),
  pink('pink', 0xF4A6C0),
  purple('purple', 0x7E57C2);

  const ReferenceColor(this.id, this.rgb);

  final String id;
  final int rgb;

  static ReferenceColor? fromRgb(int rgb) {
    for (final c in values) {
      if (c.rgb == rgb) return c;
    }
    return null;
  }
}
