import '../../../core/domain/result.dart';
import '../../wardrobe/domain/garment.dart';
import 'calendar_day.dart';
import 'wear_event.dart';

sealed class WearFailure {
  const WearFailure();
}

enum WearProblem {
  noGarments,
  tooManyGarments,

  /// Planear não é usar: não se regista o que ainda não aconteceu.
  futureDay,

  /// Peça inexistente ou eliminada.
  unknownGarment,
}

final class InvalidWear extends WearFailure {
  const InvalidWear(this.problem);
  final WearProblem problem;
}

final class WearNotFound extends WearFailure {
  const WearNotFound(this.id);
  final String id;
}

final class WearStorageFailure extends WearFailure {
  const WearStorageFailure(this.message);
  final String message;
}

typedef WearResult<T> = Result<T, WearFailure>;

/// Utilizações reais. Como no guarda-roupa, cada escrita fica guardada
/// neste dispositivo e a operação segue para o servidor na mesma transação.
abstract interface class WearRepository {
  /// Todas as utilizações não desfeitas (para lavagem e rotatividade).
  Stream<List<WearEvent>> watchAll();

  /// Utilizações (não desfeitas) de um dia, pela ordem de registo.
  Stream<List<WearEvent>> watchDay(CalendarDay day);

  /// Uma utilização não desfeita; `null` se não existir ou foi desfeita.
  Stream<WearEvent?> watchEvent(String id);

  /// Utilizações de uma peça, da mais recente para a mais antiga.
  Stream<List<WearEvent>> watchGarmentHistory(GarmentId id);

  Future<WearResult<WearEvent>> recordWear(
    CalendarDay day,
    Set<GarmentId> garments, {
    String? planEntryId,
  });

  /// Troca as peças de uma utilização: desfaz e regista outra com o mesmo
  /// dia e entrada de plano, numa só transação.
  Future<WearResult<WearEvent>> correctWear(
    String eventId,
    Set<GarmentId> garments,
  );

  /// Desfaz. Idempotente.
  Future<WearResult<void>> voidWear(String eventId);
}
