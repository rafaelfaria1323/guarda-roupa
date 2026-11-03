import '../../../core/domain/result.dart';
import '../../wardrobe/domain/garment.dart';
import '../../wardrobe/domain/garment_category.dart';
import '../../wear/domain/calendar_day.dart';
import 'care_policies.dart';
import 'cleaning_event.dart';

sealed class CareFailure {
  const CareFailure();
}

/// Peça inexistente/eliminada, dia futuro ou valor fora dos limites.
final class InvalidCare extends CareFailure {
  const InvalidCare(this.problem);
  final CareProblem problem;
}

enum CareProblem { unknownGarment, futureDay, outOfRange }

final class CleaningNotFound extends CareFailure {
  const CleaningNotFound(this.id);
  final String id;
}

final class CareStorageFailure extends CareFailure {
  const CareStorageFailure(this.message);
  final String message;
}

typedef CareResult<T> = Result<T, CareFailure>;

/// Limpezas e valores escolhidos (lavagem e rotatividade).
abstract interface class CareRepository {
  /// Limpezas não desfeitas, de todas as peças.
  Stream<List<CleaningEvent>> watchCleanings();

  Stream<CarePolicies> watchPolicies();

  Future<CareResult<CleaningEvent>> recordCleaning(
    GarmentId garment,
    CalendarDay day,
  );

  Future<CareResult<void>> voidCleaning(String id);

  /// `null` volta ao predefinido; `0` = sem aviso.
  Future<CareResult<void>> setCategoryLaundry(GarmentCategory c, int? value);

  Future<CareResult<void>> setGarmentLaundry(GarmentId g, int? value);

  /// `null` volta ao predefinido; `0` = sem intervalo.
  Future<CareResult<void>> setCategoryRotation(GarmentCategory c, int? value);

  Future<CareResult<void>> setGarmentRotation(GarmentId g, int? value);
}
