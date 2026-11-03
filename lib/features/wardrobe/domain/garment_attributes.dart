/// Atributos opcionais de uma peça. `null` (ou conjunto vazio) é
/// desconhecido: nunca se inventa um valor neutro. Os IDs são estáveis
/// (persistidos e sincronizados); a tradução é só da apresentação.
library;

enum GarmentPattern {
  plain('plain'),
  stripes('stripes'),
  checks('checks'),
  dots('dots'),
  floral('floral'),
  print('print'),
  other('other');

  const GarmentPattern(this.id);
  final String id;
  static GarmentPattern? fromId(String? id) => _byId(values, id, (v) => v.id);
}

/// Textura superficial visível. Não é composição: "malha" não prova lã.
enum SurfaceTexture {
  smooth('smooth'),
  ribbed('ribbed'),
  knit('knit'),
  textured('textured'),
  fuzzy('fuzzy');

  const SurfaceTexture(this.id);
  final String id;
  static SurfaceTexture? fromId(String? id) => _byId(values, id, (v) => v.id);
}

/// Aquecimento aproximado indicado pelo utilizador.
enum Warmth {
  light('light'),
  medium('medium'),
  warm('warm');

  const Warmth(this.id);
  final String id;
  static Warmth? fromId(String? id) => _byId(values, id, (v) => v.id);
}

/// Ocasiões iniciais confirmadas (docs/features/conjuntos-e-ocasioes.md).
enum Occasion {
  casual('casual'),
  workCasual('work_casual'),
  evening('evening');

  const Occasion(this.id);
  final String id;
  static Occasion? fromId(String? id) => _byId(values, id, (v) => v.id);
}

T? _byId<T>(List<T> values, String? id, String Function(T) idOf) {
  for (final v in values) {
    if (idOf(v) == id) return v;
  }
  return null;
}

final class GarmentAttributes {
  const GarmentAttributes({
    this.pattern,
    this.texture,
    this.warmth,
    this.rainOk,
    this.windOk,
    this.occasions = const {},
    this.material,
    this.care,
  });

  static const maxMaterialLength = 120;
  static const maxCareLength = 300;

  final GarmentPattern? pattern;
  final SurfaceTexture? texture;
  final Warmth? warmth;

  /// Adequação conhecida a chuva / vento; `null` = não se sabe.
  final bool? rainOk;
  final bool? windOk;
  final Set<Occasion> occasions;

  /// Texto da etiqueta, quando conhecido.
  final String? material;
  final String? care;

  /// Valores por coluna, como são guardados e enviados ao servidor.
  /// Ocasiões por ordem estável, para a comparação no servidor.
  Map<String, Object?> toColumns() => {
    'pattern': pattern?.id,
    'texture': texture?.id,
    'warmth': warmth?.id,
    'rain_ok': rainOk,
    'wind_ok': windOk,
    'occasions': [
      for (final o in Occasion.values)
        if (occasions.contains(o)) o.id,
    ],
    'material': material,
    'care': care,
  };

  /// Os campos podem ficar desconhecidos: passa `() => null`.
  GarmentAttributes copyWith({
    GarmentPattern? Function()? pattern,
    SurfaceTexture? Function()? texture,
    Warmth? Function()? warmth,
    bool? Function()? rainOk,
    bool? Function()? windOk,
    Set<Occasion>? occasions,
    String? Function()? material,
    String? Function()? care,
  }) => GarmentAttributes(
    pattern: pattern == null ? this.pattern : pattern(),
    texture: texture == null ? this.texture : texture(),
    warmth: warmth == null ? this.warmth : warmth(),
    rainOk: rainOk == null ? this.rainOk : rainOk(),
    windOk: windOk == null ? this.windOk : windOk(),
    occasions: occasions ?? this.occasions,
    material: material == null ? this.material : material(),
    care: care == null ? this.care : care(),
  );

  /// Algum atributo conhecido (para abrir a secção no formulário).
  bool get isEmpty => this == const GarmentAttributes();

  GarmentAttributes normalized(String? Function(String?) text) =>
      GarmentAttributes(
        pattern: pattern,
        texture: texture,
        warmth: warmth,
        rainOk: rainOk,
        windOk: windOk,
        occasions: Set.unmodifiable(occasions),
        material: text(material),
        care: text(care),
      );

  @override
  bool operator ==(Object other) =>
      other is GarmentAttributes &&
      other.pattern == pattern &&
      other.texture == texture &&
      other.warmth == warmth &&
      other.rainOk == rainOk &&
      other.windOk == windOk &&
      other.occasions.length == occasions.length &&
      other.occasions.containsAll(occasions) &&
      other.material == material &&
      other.care == care;

  @override
  int get hashCode => Object.hash(
    pattern,
    texture,
    warmth,
    rainOk,
    windOk,
    Object.hashAllUnordered(occasions),
    material,
    care,
  );
}
