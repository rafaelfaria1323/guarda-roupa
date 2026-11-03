import 'availability.dart';
import 'garment.dart';
import 'garment_category.dart';

/// Critérios de pesquisa do catálogo. Conjuntos vazios significam "todos".
final class GarmentFilter {
  const GarmentFilter({
    this.categories = const {},
    this.groups = const {},
    this.availability = const {},
    this.includeArchived = false,
    this.text,
  });

  final Set<GarmentCategory> categories;
  final Set<CategoryGroup> groups;
  final Set<Availability> availability;
  final bool includeArchived;

  /// Pesquisa em nome, marca e notas, sem distinguir maiúsculas nem acentos.
  final String? text;

  GarmentFilter copyWith({
    Set<CategoryGroup>? groups,
    Set<Availability>? availability,
    bool? includeArchived,
    String? text,
  }) => GarmentFilter(
    categories: categories,
    groups: groups ?? this.groups,
    availability: availability ?? this.availability,
    includeArchived: includeArchived ?? this.includeArchived,
    text: text ?? this.text,
  );

  /// Há algum critério além de "não arquivadas"?
  bool get isActive =>
      categories.isNotEmpty ||
      groups.isNotEmpty ||
      availability.isNotEmpty ||
      includeArchived ||
      (text?.trim().isNotEmpty ?? false);

  @override
  bool operator ==(Object other) =>
      other is GarmentFilter &&
      _sameSet(other.categories, categories) &&
      _sameSet(other.groups, groups) &&
      _sameSet(other.availability, availability) &&
      other.includeArchived == includeArchived &&
      (other.text ?? '') == (text ?? '');

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(categories),
    Object.hashAllUnordered(groups),
    Object.hashAllUnordered(availability),
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
    final query = _fold(text?.trim() ?? '');
    if (query.isEmpty) return true;
    return [
      garment.name,
      garment.brand,
      garment.notes,
    ].whereType<String>().any((field) => _fold(field).contains(query));
  }

  static const _accents = {
    'á': 'a', 'à': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', //
    'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e', //
    'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i', //
    'ó': 'o', 'ò': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o', //
    'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u', //
    'ç': 'c', 'ñ': 'n',
  };

  static String _fold(String value) {
    final buffer = StringBuffer();
    for (final char in value.toLowerCase().split('')) {
      buffer.write(_accents[char] ?? char);
    }
    return buffer.toString();
  }
}
