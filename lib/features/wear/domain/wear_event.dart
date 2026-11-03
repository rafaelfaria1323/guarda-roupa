import '../../wardrobe/domain/garment.dart';
import 'calendar_day.dart';

/// "Vesti estas peças neste dia", confirmado pelo utilizador (P-08).
///
/// Só eventos confirmados contam como utilização; planear não cria eventos.
final class WearEvent {
  const WearEvent({
    required this.id,
    required this.wornOn,
    required this.garmentIds,
    required this.createdAt,
    this.planEntryId,
  });

  final String id;
  final CalendarDay wornOn;
  final List<GarmentId> garmentIds;

  /// Entrada do plano confirmada, se veio do plano. A mesma entrada
  /// confirmada em dois dispositivos conta uma só vez.
  final String? planEntryId;
  final DateTime createdAt;
}

abstract final class WearRules {
  /// Igual ao limite do servidor (`wear_garments_valid`).
  static const maxGarments = 30;
}
