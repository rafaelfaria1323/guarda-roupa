import 'dart:convert';

import '../domain/availability.dart';
import '../domain/garment.dart';
import '../domain/garment_category.dart';
import '../domain/garment_color.dart';

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

  static String? iso(DateTime? value) => value?.toUtc().toIso8601String();

  static DateTime? _date(Object? value) =>
      value is String ? DateTime.tryParse(value)?.toUtc() : null;
}
