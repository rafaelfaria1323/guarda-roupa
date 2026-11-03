import '../../../core/domain/result.dart';
import 'availability.dart';
import 'garment.dart';
import 'garment_filter.dart';

/// Falhas possíveis de uma operação do guarda-roupa, distintas entre si.
sealed class WardrobeFailure {
  const WardrobeFailure();
}

/// Os dados não cumprem as regras (ver `GarmentRules.validate`).
final class InvalidDraft extends WardrobeFailure {
  const InvalidDraft(this.problems);
  final List<DraftProblem> problems;
}

final class GarmentNotFound extends WardrobeFailure {
  const GarmentNotFound(this.id);
  final GarmentId id;
}

/// A peça foi eliminada (tombstone). Não se ressuscita (ADR-008).
final class GarmentDeleted extends WardrobeFailure {
  const GarmentDeleted(this.id);
  final GarmentId id;
}

/// Falha da persistência local (disco cheio, base corrompida, ...).
final class StorageFailure extends WardrobeFailure {
  const StorageFailure(this.message);
  final String message;
}

typedef WardrobeResult<T> = Result<T, WardrobeFailure>;

/// Contrato do guarda-roupa, orientado ao negócio (ADR-002).
///
/// As implementações escrevem na base local e registam a operação para
/// sincronização na mesma transação. "Guardado" significa guardado neste
/// dispositivo, não aceite pelo servidor; o estado de sincronização é
/// exposto à parte.
abstract interface class WardrobeRepository {
  /// Observa as peças que satisfazem o filtro. Emite de novo quando mudam.
  /// Erros de leitura chegam como erro do stream, nunca como lista vazia.
  Stream<List<Garment>> watchGarments(GarmentFilter filter);

  Stream<Garment?> watchGarment(GarmentId id);

  Future<WardrobeResult<Garment>> addGarment(GarmentDraft draft);

  Future<WardrobeResult<Garment>> updateGarment(
    GarmentId id,
    GarmentDraft draft,
  );

  /// Cria uma nova peça com os dados de `source`, novo ID e histórico vazio.
  Future<WardrobeResult<Garment>> duplicateGarment(GarmentId source);

  /// Transição explícita de disponibilidade feita pelo utilizador.
  Future<WardrobeResult<Garment>> setAvailability(
    GarmentId id,
    Availability availability,
  );

  /// Arquiva sem perder histórico. Idempotente.
  Future<WardrobeResult<Garment>> archiveGarment(GarmentId id);

  Future<WardrobeResult<Garment>> unarchiveGarment(GarmentId id);
}
