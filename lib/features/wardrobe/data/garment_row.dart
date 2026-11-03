import 'dart:convert';

import '../domain/availability.dart';
import '../domain/garment.dart';
import '../domain/garment_attributes.dart';
import '../domain/garment_category.dart';
import '../domain/garment_color.dart';
import '../domain/garment_photo.dart';

/// Conversão entre linhas SQLite/JSON e o domínio.
///
/// Uma linha com valores desconhecidos (ex.: categoria criada por uma versão
/// mais recente da app) é ignorada pelo leitor, em vez de inventar valores.
abstract final class GarmentRow {
  static Garment? fromRow(Map<String, Object?> row) {
    final category = GarmentCategory.fromId(row['category'] as String? ?? '');
    final availability = Availability.fromId(
      row['availability'] as String? ?? '',
    );
    final createdAt = _date(row['created_at']);
    if (category == null || availability == null || createdAt == null) {
      return null;
    }
    return Garment(
      id: GarmentId(row['id']! as String),
      category: category,
      name: row['name'] as String?,
      brand: row['brand'] as String?,
      notes: row['notes'] as String?,
      colors: decodeColors(row['colors'] as String?),
      photos: decodePhotos(row['photos'] as String?),
      attributes: attributesFrom(row),
      availability: availability,
      archivedAt: _date(row['archived_at']),
      createdAt: createdAt,
      updatedAt: _date(row['updated_at']) ?? createdAt,
    );
  }

  static List<Object?> colorsJson(List<GarmentColor> colors) => [
    for (final c in colors)
      {'rgb': c.rgb, 'proportion': c.proportion, 'confirmed': c.confirmed},
  ];

  static String encodeColors(List<GarmentColor> colors) =>
      jsonEncode(colorsJson(colors));

  static List<GarmentColor> decodeColors(String? json) {
    if (json == null || json.isEmpty) return const [];
    final decoded = jsonDecode(json);
    if (decoded is! List) return const [];
    return List.unmodifiable([
      for (final item in decoded)
        if (item case {
          'rgb': final int rgb,
          'proportion': final num proportion,
          'confirmed': final bool confirmed,
        })
          ?GarmentColor.create(
            rgb: rgb,
            proportion: proportion.toDouble(),
            confirmed: confirmed,
          ),
    ]);
  }

  /// Valores desconhecidos (ex.: de uma versão mais recente) ficam
  /// desconhecidos, em vez de a peça desaparecer.
  static GarmentAttributes attributesFrom(Map<String, Object?> row) {
    final occasions = <Occasion>{};
    final raw = row['occasions'];
    if (raw is String && raw.isNotEmpty) {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        for (final id in decoded) {
          if (Occasion.fromId(id is String ? id : null) case final o?) {
            occasions.add(o);
          }
        }
      }
    }
    return GarmentAttributes(
      pattern: GarmentPattern.fromId(row['pattern'] as String?),
      texture: SurfaceTexture.fromId(row['texture'] as String?),
      warmth: Warmth.fromId(row['warmth'] as String?),
      rainOk: _bool(row['rain_ok']),
      windOk: _bool(row['wind_ok']),
      occasions: Set.unmodifiable(occasions),
      material: row['material'] as String?,
      care: row['care'] as String?,
    );
  }

  /// Colunas SQLite: booleanos como 0/1, ocasiões como JSON.
  static Map<String, Object?> attributeColumns(GarmentAttributes a) => {
    for (final MapEntry(:key, :value) in a.toColumns().entries)
      key: switch (value) {
        final bool b => b ? 1 : 0,
        final List<Object?> list => jsonEncode(list),
        _ => value,
      },
  };

  static bool? _bool(Object? value) => switch (value) {
    final int i => i != 0,
    final bool b => b,
    // O PowerSync guarda booleanos do Postgres como texto/inteiro.
    'true' || '1' => true,
    'false' || '0' => false,
    _ => null,
  };

  static List<Object?> photosJson(List<GarmentPhoto> photos) => [
    for (final p in photos) photoJson(p),
  ];

  static Map<String, Object?> photoJson(GarmentPhoto p) => {
    'id': p.id,
    'width': p.width,
    'height': p.height,
    'bytes': p.bytes,
    'thumb_bytes': p.thumbBytes,
    'sha256': p.sha256,
  };

  static String encodePhotos(List<GarmentPhoto> photos) =>
      jsonEncode(photosJson(photos));

  static List<GarmentPhoto> decodePhotos(String? json) {
    if (json == null || json.isEmpty) return const [];
    final decoded = jsonDecode(json);
    if (decoded is! List) return const [];
    return List.unmodifiable([
      for (final item in decoded)
        if (item case {
          'id': final String id,
          'width': final int width,
          'height': final int height,
          'bytes': final int bytes,
          'thumb_bytes': final int thumbBytes,
          'sha256': final String sha256,
        })
          GarmentPhoto(
            id: id,
            width: width,
            height: height,
            bytes: bytes,
            thumbBytes: thumbBytes,
            sha256: sha256,
          ),
    ]);
  }

  static String? iso(DateTime? value) => value?.toUtc().toIso8601String();

  static DateTime? _date(Object? value) =>
      value is String ? DateTime.tryParse(value)?.toUtc() : null;
}
