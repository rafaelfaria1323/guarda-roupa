import 'dart:typed_data';

import '../../../core/domain/result.dart';
import '../../wardrobe/domain/garment_attributes.dart';
import '../../wardrobe/domain/garment_category.dart';
import '../../wardrobe/domain/garment_color.dart';
import '../../wardrobe/domain/reference_color.dart';

/// Ler uma foto com o Gemini (opcional, docs/features/ia-gemini.md). Só
/// sugestões: a app nunca grava nada sem o utilizador ver.
abstract interface class PhotoReader {
  /// O que a foto de uma peça mostra.
  Future<Result<GarmentReading, PhotoReadFailure>> readGarment(Uint8List jpeg);

  /// O que diz a etiqueta de cuidados.
  Future<Result<LabelReading, PhotoReadFailure>> readLabel(Uint8List jpeg);
}

enum PhotoReadFailure {
  /// O servidor não tem a chave do Gemini.
  notConfigured,

  /// Sem sessão ou fora da lista de utilizadores.
  notAllowed,

  /// Muitas fotos seguidas (limite da app, por hora e por dia).
  limit,

  /// A quota grátis do Gemini acabou por agora.
  busy,

  /// Sem rede ou resposta estragada.
  failed,
}

/// Valores que a app conhece; o resto vem `null`.
final class GarmentReading {
  const GarmentReading({
    this.category,
    this.name,
    this.colors = const [],
    this.pattern,
    this.texture,
    this.warmth,
    this.formality,
  });

  factory GarmentReading.fromJson(Map<String, Object?> json) {
    final colors = <GarmentColor>[];
    var total = 0.0;
    for (final c in json['colors'] is List ? json['colors']! as List : []) {
      if (c is! Map) continue;
      final ref = _reference(c['color']);
      final share = c['share'];
      if (ref == null || share is! num) continue;
      final proportion = share / 100;
      if (total + proportion > 1 + 1e-9) break;
      final color = GarmentColor.create(rgb: ref.rgb, proportion: proportion);
      if (color == null) continue;
      colors.add(color);
      total += proportion;
    }
    final name = json['name'];
    return GarmentReading(
      category: switch (json['category']) {
        final String id => GarmentCategory.fromId(id),
        _ => null,
      },
      name: name is String && name.trim().isNotEmpty ? name.trim() : null,
      colors: colors,
      pattern: GarmentPattern.fromId(_string(json['pattern'])),
      texture: SurfaceTexture.fromId(_string(json['texture'])),
      warmth: Warmth.fromId(_string(json['warmth'])),
      formality: Formality.fromId(_string(json['formality'])),
    );
  }

  final GarmentCategory? category;
  final String? name;

  /// Por confirmar (`confirmed: false`), como as cores sugeridas sem IA.
  final List<GarmentColor> colors;
  final GarmentPattern? pattern;
  final SurfaceTexture? texture;
  final Warmth? warmth;
  final Formality? formality;

  /// Junta aos atributos só o que ainda não se sabe.
  GarmentAttributes fillUnknown(GarmentAttributes a) => a.copyWith(
    pattern: () => a.pattern ?? pattern,
    texture: () => a.texture ?? texture,
    warmth: () => a.warmth ?? warmth,
    formality: () => a.formality ?? formality,
  );
}

final class LabelReading {
  const LabelReading({this.wash, this.tumbleDry, this.material, this.care});

  factory LabelReading.fromJson(Map<String, Object?> json) => LabelReading(
    wash: WashCare.fromId(_string(json['wash'])),
    tumbleDry: json['tumble_dry'] is bool ? json['tumble_dry']! as bool : null,
    material: _text(json['material'], GarmentAttributes.maxMaterialLength),
    care: _text(json['care'], GarmentAttributes.maxCareLength),
  );

  final WashCare? wash;
  final bool? tumbleDry;
  final String? material;
  final String? care;

  bool get isEmpty =>
      wash == null && tumbleDry == null && material == null && care == null;
}

String? _string(Object? v) => v is String ? v : null;

String? _text(Object? v, int max) {
  if (v is! String) return null;
  final t = v.trim();
  if (t.isEmpty) return null;
  return t.length > max ? t.substring(0, max).trim() : t;
}

ReferenceColor? _reference(Object? id) {
  for (final c in ReferenceColor.values) {
    if (c.id == id) return c;
  }
  return null;
}
