import 'package:uuid/uuid.dart';

import '../../../core/domain/clock.dart';
import '../../../core/domain/result.dart';
import 'availability.dart';
import 'garment.dart';
import 'garment_photo.dart';

typedef IdGenerator = String Function();

String _uuidV4() => const Uuid().v4();

/// Regras de criação e alteração de peças, partilhadas por todas as
/// implementações do repositório.
final class GarmentFactory {
  const GarmentFactory({
    this.clock = const SystemClock(),
    this.newId = _uuidV4,
  });

  final Clock clock;
  final IdGenerator newId;

  Result<Garment, List<DraftProblem>> create(GarmentDraft draft) {
    final problems = GarmentRules.validate(draft);
    if (problems.isNotEmpty) return Err(problems);
    final now = clock.nowUtc();
    return Ok(
      Garment(
        id: GarmentId(newId()),
        category: draft.category,
        name: GarmentRules.normalizeText(draft.name),
        brand: GarmentRules.normalizeText(draft.brand),
        notes: GarmentRules.normalizeText(draft.notes),
        colors: List.unmodifiable(draft.colors),
        attributes: draft.attributes.normalized(GarmentRules.normalizeText),
        availability: Availability.available,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  /// Aplica a edição dos dados descritivos. Mantém ID, disponibilidade,
  /// arquivo e data de criação.
  Result<Garment, List<DraftProblem>> edit(
    Garment garment,
    GarmentDraft draft,
  ) {
    final problems = GarmentRules.validate(draft);
    if (problems.isNotEmpty) return Err(problems);
    return Ok(
      Garment(
        id: garment.id,
        category: draft.category,
        name: GarmentRules.normalizeText(draft.name),
        brand: GarmentRules.normalizeText(draft.brand),
        notes: GarmentRules.normalizeText(draft.notes),
        colors: List.unmodifiable(draft.colors),
        attributes: draft.attributes.normalized(GarmentRules.normalizeText),
        photos: garment.photos,
        availability: garment.availability,
        archivedAt: garment.archivedAt,
        createdAt: garment.createdAt,
        updatedAt: clock.nowUtc(),
      ),
    );
  }

  Garment withAvailability(Garment garment, Availability availability) =>
      _copy(garment, availability: availability);

  /// Idempotente: arquivar uma peça arquivada mantém a data original.
  Garment archive(Garment garment) =>
      garment.isArchived ? garment : _copy(garment, archivedAt: clock.nowUtc());

  Garment unarchive(Garment garment) =>
      garment.isArchived ? _copy(garment, clearArchive: true) : garment;

  Garment withPhotos(Garment garment, List<GarmentPhoto> photos) =>
      _copy(garment, photos: List.unmodifiable(photos));

  Garment _copy(
    Garment g, {
    Availability? availability,
    DateTime? archivedAt,
    bool clearArchive = false,
    List<GarmentPhoto>? photos,
  }) => Garment(
    id: g.id,
    category: g.category,
    name: g.name,
    brand: g.brand,
    notes: g.notes,
    colors: g.colors,
    attributes: g.attributes,
    photos: photos ?? g.photos,
    availability: availability ?? g.availability,
    archivedAt: clearArchive ? null : (archivedAt ?? g.archivedAt),
    createdAt: g.createdAt,
    updatedAt: clock.nowUtc(),
  );
}
