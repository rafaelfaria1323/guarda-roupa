import '../../../core/domain/result.dart';
import 'inspiration.dart';
import 'style_preference.dart';

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

sealed class PreferenceFailure {
  const PreferenceFailure();
}

final class InvalidPreference extends PreferenceFailure {
  const InvalidPreference();
}

/// Já há uma preferência ativa para o mesmo assunto, valor e contexto.
final class DuplicatePreference extends PreferenceFailure {
  const DuplicatePreference(this.existingId);
  final String existingId;
}

final class PreferenceNotFound extends PreferenceFailure {
  const PreferenceNotFound(this.id);
  final String id;
}

final class PreferenceStorageFailure extends PreferenceFailure {
  const PreferenceStorageFailure(this.detail);
  final String detail;
}

typedef PreferenceResult<T> = Result<T, PreferenceFailure>;

abstract interface class StylePreferenceRepository {
  /// Mais recentes primeiro.
  Stream<List<StylePreference>> watchPreferences();
  Stream<StylePreference?> watchPreference(String id);
  Future<PreferenceResult<StylePreference>> createPreference(
    PreferenceDraft draft,
  );

  /// Cria as que ainda não existem (as repetidas são ignoradas) e devolve
  /// quantas criou.
  Future<PreferenceResult<int>> createPreferences(List<PreferenceDraft> drafts);

  /// Muda valor, posição e contexto; o assunto e a origem ficam.
  Future<PreferenceResult<StylePreference>> updatePreference(
    String id,
    PreferenceDraft draft,
  );
  Future<PreferenceResult<void>> deletePreference(String id);
}
