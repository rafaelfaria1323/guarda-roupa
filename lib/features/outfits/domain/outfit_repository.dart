import '../../../core/domain/result.dart';
import 'outfit.dart';

sealed class OutfitFailure {
  const OutfitFailure();
}

final class InvalidOutfit extends OutfitFailure {
  const InvalidOutfit(this.problem);
  final OutfitProblem problem;
}

/// Alguma peça não existe (ou foi eliminada entretanto).
final class UnknownOutfitGarment extends OutfitFailure {
  const UnknownOutfitGarment();
}

final class OutfitNotFound extends OutfitFailure {
  const OutfitNotFound(this.id);
  final String id;
}

final class OutfitStorageFailure extends OutfitFailure {
  const OutfitStorageFailure(this.detail);
  final String detail;
}

typedef OutfitResult<T> = Result<T, OutfitFailure>;

abstract interface class OutfitRepository {
  /// Mais recentes primeiro.
  Stream<List<Outfit>> watchOutfits();
  Stream<Outfit?> watchOutfit(String id);

  /// Só peças ativas (não arquivadas, não eliminadas).
  Future<OutfitResult<Outfit>> createOutfit(OutfitDraft draft);

  /// Peças arquivadas que já estavam no conjunto podem ficar; novas têm de
  /// estar ativas.
  Future<OutfitResult<Outfit>> updateOutfit(String id, OutfitDraft draft);
  Future<OutfitResult<void>> deleteOutfit(String id);
}
