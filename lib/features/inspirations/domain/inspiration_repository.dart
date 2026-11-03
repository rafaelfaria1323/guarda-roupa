import '../../../core/domain/result.dart';
import 'inspiration.dart';

sealed class InspirationFailure {
  const InspirationFailure();
}

final class InvalidInspiration extends InspirationFailure {
  const InvalidInspiration(this.problem);
  final InspirationProblem problem;
}

final class InspirationNotFound extends InspirationFailure {
  const InspirationNotFound(this.id);
  final String id;
}

final class InspirationStorageFailure extends InspirationFailure {
  const InspirationStorageFailure(this.detail);
  final String detail;
}

typedef InspirationResult<T> = Result<T, InspirationFailure>;

abstract interface class InspirationRepository {
  /// Mais recentes primeiro.
  Stream<List<Inspiration>> watchInspirations();
  Stream<Inspiration?> watchInspiration(String id);
  Future<InspirationResult<Inspiration>> createInspiration(
    InspirationDraft draft,
  );
  Future<InspirationResult<Inspiration>> updateInspiration(
    String id,
    InspirationDraft draft,
  );
  Future<InspirationResult<void>> deleteInspiration(String id);
}
