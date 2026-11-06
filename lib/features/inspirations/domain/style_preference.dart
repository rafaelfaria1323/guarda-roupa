import '../../wardrobe/domain/garment_attributes.dart';
import 'inspiration.dart';

/// Sobre o que é a preferência. Os ids são estáveis (sincronizados).
enum PreferenceSubject {
  color('color'),
  pattern('pattern'),
  texture('texture'),
  formality('formality'),
  combo('combo');

  const PreferenceSubject(this.id);
  final String id;

  static PreferenceSubject? fromId(String? id) {
    for (final s in values) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// Valores possíveis (para cores: RGB em decimal).
  bool accepts(String value) => switch (this) {
    color => switch (int.tryParse(value)) {
      final rgb? => rgb >= 0 && rgb <= 0xFFFFFF && '$rgb' == value,
      null => false,
    },
    pattern => GarmentPattern.fromId(value) != null,
    texture => SurfaceTexture.fromId(value) != null,
    formality => Formality.fromId(value) != null,
    combo => StyleCombo.fromId(value) != null,
  };
}

/// Combinações de cor que se podem preferir ou evitar.
enum StyleCombo {
  /// Peças grandes em cores neutras.
  neutralBase('neutral_base'),

  /// Uma só cor forte no conjunto.
  singleAccent('single_accent'),

  /// Tons próximos da mesma cor.
  tonal('tonal'),

  /// Peças grandes claras com escuras (muito contraste).
  highContrast('high_contrast'),

  /// Peças grandes de luminosidade parecida (pouco contraste).
  lowContrast('low_contrast');

  const StyleCombo(this.id);
  final String id;

  static StyleCombo? fromId(String? id) {
    for (final c in values) {
      if (c.id == id) return c;
    }
    return null;
  }
}

enum PreferenceStance {
  like('like'),
  avoid('avoid');

  const PreferenceStance(this.id);
  final String id;

  static PreferenceStance? fromId(String? id) {
    for (final s in values) {
      if (s.id == id) return s;
    }
    return null;
  }
}

/// Preferência explícita: "gosto"/"evito" de um assunto, só nas
/// [occasions] indicadas (vazio = sempre). Nunca é posse: no motor é só
/// uma componente da pontuação de peças que existem.
final class StylePreference {
  const StylePreference({
    required this.id,
    required this.subject,
    required this.value,
    required this.stance,
    required this.createdAt,
    required this.updatedAt,
    this.occasions = const {},
    this.inspirationId,
  });

  final String id;
  final PreferenceSubject subject;
  final String value;
  final PreferenceStance stance;
  final Set<Occasion> occasions;

  /// Inspiração de onde nasceu (pode já ter sido eliminada).
  final String? inspirationId;
  final DateTime createdAt;
  final DateTime updatedAt;

  PreferenceDraft toDraft() => PreferenceDraft(
    subject: subject,
    value: value,
    stance: stance,
    occasions: occasions,
    inspirationId: inspirationId,
  );
}

final class PreferenceDraft {
  const PreferenceDraft({
    required this.subject,
    required this.value,
    required this.stance,
    this.occasions = const {},
    this.inspirationId,
  });

  final PreferenceSubject subject;
  final String value;
  final PreferenceStance stance;
  final Set<Occasion> occasions;
  final String? inspirationId;

  /// Mesmo assunto, valor e contexto: só pode haver uma preferência ativa.
  bool sameTarget(PreferenceDraft other) =>
      other.subject == subject &&
      other.value == value &&
      other.occasions.length == occasions.length &&
      other.occasions.containsAll(occasions);

  /// "Gosto" de cada etiqueta de uma inspiração, no contexto das ocasiões
  /// dela. O utilizador escolhe quais quer antes de criar.
  static List<PreferenceDraft> fromInspiration(Inspiration i) => [
    for (final rgb in i.palette) _like(i, PreferenceSubject.color, '$rgb'),
    if (i.formality case final f?) _like(i, PreferenceSubject.formality, f.id),
    for (final p in GarmentPattern.values)
      if (i.patterns.contains(p)) _like(i, PreferenceSubject.pattern, p.id),
    for (final t in SurfaceTexture.values)
      if (i.textures.contains(t)) _like(i, PreferenceSubject.texture, t.id),
  ];

  static PreferenceDraft _like(
    Inspiration i,
    PreferenceSubject subject,
    String value,
  ) => PreferenceDraft(
    subject: subject,
    value: value,
    stance: PreferenceStance.like,
    occasions: i.occasions,
    inspirationId: i.id,
  );
}
