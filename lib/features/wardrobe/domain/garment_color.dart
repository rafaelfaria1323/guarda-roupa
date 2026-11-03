/// Cor de uma peça com a respetiva proporção visível.
final class GarmentColor {
  const GarmentColor._({
    required this.rgb,
    required this.proportion,
    required this.confirmed,
  });

  /// Valida e cria uma cor. Devolve `null` se os valores forem inválidos.
  static GarmentColor? create({
    required int rgb,
    required double proportion,
    bool confirmed = false,
  }) {
    if (rgb < 0 || rgb > 0xFFFFFF) return null;
    if (proportion.isNaN || proportion <= 0 || proportion > 1) return null;
    return GarmentColor._(
      rgb: rgb,
      proportion: proportion,
      confirmed: confirmed,
    );
  }

  /// RGB de referência, `0xRRGGBB`.
  final int rgb;

  /// Fração da peça ocupada por esta cor, em ]0, 1].
  final double proportion;

  /// `true` se o utilizador confirmou (e não apenas uma sugestão).
  final bool confirmed;

  @override
  bool operator ==(Object other) =>
      other is GarmentColor &&
      other.rgb == rgb &&
      other.proportion == proportion &&
      other.confirmed == confirmed;

  @override
  int get hashCode => Object.hash(rgb, proportion, confirmed);
}
