import 'availability.dart';
import 'garment.dart';
import 'garment_attributes.dart';
import 'garment_category.dart';

/// Critérios de pesquisa do catálogo. Conjuntos vazios significam "todos".
final class GarmentFilter {
  const GarmentFilter({
    this.categories = const {},
    this.groups = const {},
    this.availability = const {},
    this.occasions = const {},
    this.includeArchived = false,
    this.text,
  });

  final Set<GarmentCategory> categories;
  final Set<CategoryGroup> groups;
  final Set<Availability> availability;

  /// Peças marcadas com alguma destas ocasiões (sem marcação = não sei, não
  /// aparece).
  final Set<Occasion> occasions;
  final bool includeArchived;

  /// Pesquisa em nome, marca e notas, sem distinguir maiúsculas nem acentos.
  final String? text;

  GarmentFilter copyWith({
    Set<CategoryGroup>? groups,
    Set<Availability>? availability,
    Set<Occasion>? occasions,
    bool? includeArchived,
    String? text,
  }) => GarmentFilter(
    categories: categories,
    groups: groups ?? this.groups,
    availability: availability ?? this.availability,
    occasions: occasions ?? this.occasions,
    includeArchived: includeArchived ?? this.includeArchived,
    text: text ?? this.text,
  );

  /// Há algum critério além de "não arquivadas"?
  bool get isActive =>
      categories.isNotEmpty ||
      groups.isNotEmpty ||
      availability.isNotEmpty ||
      occasions.isNotEmpty ||
      includeArchived ||
      (text?.trim().isNotEmpty ?? false);

  @override
  bool operator ==(Object other) =>
      other is GarmentFilter &&
      _sameSet(other.categories, categories) &&
      _sameSet(other.groups, groups) &&
      _sameSet(other.availability, availability) &&
      _sameSet(other.occasions, occasions) &&
      other.includeArchived == includeArchived &&
      (other.text ?? '') == (text ?? '');

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(categories),
    Object.hashAllUnordered(groups),
    Object.hashAllUnordered(availability),
    Object.hashAllUnordered(occasions),
    includeArchived,
    text ?? '',
  );

  static bool _sameSet<T>(Set<T> a, Set<T> b) =>
      a.length == b.length && a.containsAll(b);

  bool matches(Garment garment) {
    if (!includeArchived && garment.isArchived) return false;
    if (categories.isNotEmpty && !categories.contains(garment.category)) {
      return false;
    }
    if (groups.isNotEmpty && !groups.contains(garment.category.group)) {
      return false;
    }
    if (availability.isNotEmpty &&
        !availability.contains(garment.availability)) {
      return false;
    }
    if (occasions.isNotEmpty &&
        !garment.attributes.occasions.any(occasions.contains)) {
      return false;
    }
    final query = fold(text?.trim() ?? '');
    if (query.isEmpty) return true;
    return [
      garment.name,
      garment.brand,
      garment.notes,
    ].whereType<String>().any((field) => fold(field).contains(query));
  }

  static const _accents = {
    'á': 'a', 'à': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', //
    'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e', //
    'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i', //
    'ó': 'o', 'ò': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o', //
    'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u', //
    'ç': 'c', 'ñ': 'n',
  };

  /// Minúsculas e sem acentos, para comparar texto livre.
  static String fold(String value) {
    final buffer = StringBuffer();
    for (final char in value.toLowerCase().split('')) {
      buffer.write(_accents[char] ?? char);
    }
    return buffer.toString();
  }
}
