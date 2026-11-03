import 'availability.dart';
import 'garment_attributes.dart';
import 'garment_category.dart';
import 'garment_color.dart';
import 'garment_photo.dart';

/// Identidade estável de uma peça física (UUID), igual em todos os
/// dispositivos.
extension type const GarmentId(String value) {}

/// Uma peça física. Duas unidades iguais são duas peças, com IDs e
/// históricos distintos.
///
/// Os campos opcionais são desconhecidos quando `null`; nunca se inventam
/// valores neutros.
final class Garment {
  const Garment({
    required this.id,
    required this.category,
    required this.availability,
    required this.createdAt,
    required this.updatedAt,
    this.name,
    this.brand,
    this.notes,
    this.colors = const [],
    this.attributes = const GarmentAttributes(),
    this.photos = const [],
    this.archivedAt,
  });

  final GarmentId id;
  final GarmentCategory category;
  final String? name;
  final String? brand;
  final String? notes;
  final List<GarmentColor> colors;
  final GarmentAttributes attributes;

  /// A primeira é a capa. No máximo [PhotoRules.maxPerGarment].
  final List<GarmentPhoto> photos;
  final Availability availability;

  /// Peças arquivadas mantêm o histórico mas não são candidatas.
  final DateTime? archivedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isArchived => archivedAt != null;

  /// Pode ser proposta pelo motor: não arquivada e disponível.
  bool get isCandidate => !isArchived && availability.isAvailable;
}

/// Dados para criar ou editar uma peça. Só a categoria é obrigatória.
final class GarmentDraft {
  const GarmentDraft({
    required this.category,
    this.name,
    this.brand,
    this.notes,
    this.colors = const [],
    this.attributes = const GarmentAttributes(),
  });

  /// Copia os dados descritivos de uma peça semelhante. A nova peça terá ID
  /// próprio, histórico vazio e disponibilidade inicial.
  factory GarmentDraft.duplicateOf(Garment source) => GarmentDraft(
    category: source.category,
    name: source.name,
    brand: source.brand,
    notes: source.notes,
    colors: source.colors,
    attributes: source.attributes,
  );

  final GarmentCategory category;
  final String? name;
  final String? brand;
  final String? notes;
  final List<GarmentColor> colors;
  final GarmentAttributes attributes;
}

enum DraftProblem {
  nameTooLong,
  brandTooLong,
  notesTooLong,
  colorsExceedWhole,
  materialTooLong,
  careTooLong,
}

abstract final class GarmentRules {
  static const maxNameLength = 80;
  static const maxBrandLength = 60;
  static const maxNotesLength = 1000;

  /// Tolerância para arredondamentos na soma das proporções.
  static const _epsilon = 1e-6;

  static List<DraftProblem> validate(GarmentDraft draft) {
    final total = draft.colors.fold<double>(0, (sum, c) => sum + c.proportion);
    return [
      if ((draft.name?.length ?? 0) > maxNameLength) DraftProblem.nameTooLong,
      if ((draft.brand?.length ?? 0) > maxBrandLength)
        DraftProblem.brandTooLong,
      if ((draft.notes?.length ?? 0) > maxNotesLength)
        DraftProblem.notesTooLong,
      if (total > 1 + _epsilon) DraftProblem.colorsExceedWhole,
      if ((draft.attributes.material?.trim().length ?? 0) >
          GarmentAttributes.maxMaterialLength)
        DraftProblem.materialTooLong,
      if ((draft.attributes.care?.trim().length ?? 0) >
          GarmentAttributes.maxCareLength)
        DraftProblem.careTooLong,
    ];
  }

  /// Remove espaços e transforma texto vazio em desconhecido (`null`).
  static String? normalizeText(String? value) {
    final trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }
}
