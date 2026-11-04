import '../../../core/domain/result.dart';
import '../../wear/domain/calendar_day.dart';
import 'plan_entry.dart';

sealed class PlanFailure {
  const PlanFailure();
}

final class InvalidPlan extends PlanFailure {
  const InvalidPlan(this.problem);
  final PlanProblem problem;
}

/// Alguma peça não existe, foi eliminada ou (sendo nova) está arquivada.
final class UnknownPlanGarment extends PlanFailure {
  const UnknownPlanGarment();
}

final class PlanEntryNotFound extends PlanFailure {
  const PlanEntryNotFound(this.id);
  final String id;
}

final class PlanStorageFailure extends PlanFailure {
  const PlanStorageFailure(this.detail);
  final String detail;
}

typedef PlanResult<T> = Result<T, PlanFailure>;

abstract interface class PlanRepository {
  /// Entradas ativas de [from] a [from] + [days] − 1, por dia.
  Stream<List<PlanEntry>> watchDays(CalendarDay from, {int days = 7});

  /// Cria a entrada do dia ou altera a que existe (só os campos que
  /// mudaram, com a versão em que se baseia).
  Future<PlanResult<PlanEntry>> saveDay(CalendarDay day, PlanDraft draft);

  /// Aceita ou rejeita a proposta pendente da entrada.
  Future<PlanResult<void>> resolveProposal(String id, {required bool accept});

  Future<PlanResult<void>> deleteEntry(String id);
}
