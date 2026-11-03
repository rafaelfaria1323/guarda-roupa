import '../../wardrobe/domain/garment.dart';
import '../../wardrobe/domain/garment_category.dart';
import '../../wear/domain/calendar_day.dart';
import '../../wear/domain/wear_event.dart';
import 'care_policies.dart';
import 'cleaning_event.dart';

/// Recomendação de lavagem (P-07): aviso informativo a partir das
/// utilizações confirmadas desde a última limpeza registada. Nunca muda a
/// disponibilidade.
abstract final class LaundryPolicy {
  /// Referência USU/ACI aprovada em P-07. `0` = sem aviso.
  static int defaultFor(GarmentCategory category) => switch (category) {
    GarmentCategory.tShirt || GarmentCategory.top => 1,
    GarmentCategory.shirt || GarmentCategory.polo => 2,
    GarmentCategory.sweater ||
    GarmentCategory.sweatshirt ||
    GarmentCategory.cardigan ||
    GarmentCategory.trousers ||
    GarmentCategory.jeans ||
    GarmentCategory.shorts ||
    GarmentCategory.skirt ||
    GarmentCategory.dress ||
    GarmentCategory.jumpsuit => 4,
    GarmentCategory.jacket ||
    GarmentCategory.blazer ||
    GarmentCategory.coat ||
    GarmentCategory.raincoat ||
    GarmentCategory.sneakers ||
    GarmentCategory.shoes ||
    GarmentCategory.boots ||
    GarmentCategory.sandals ||
    GarmentCategory.accessory ||
    GarmentCategory.other => 0,
  };

  /// Peça > categoria > predefinido.
  static int thresholdFor(Garment garment, CarePolicies policies) =>
      policies.laundryByGarment[garment.id] ??
      policies.laundryByCategory[garment.category] ??
      defaultFor(garment.category);

  /// Estado de cada peça.
  static Map<GarmentId, LaundryState> evaluate({
    required Iterable<Garment> garments,
    required Iterable<WearEvent> wears,
    required Iterable<CleaningEvent> cleanings,
    required CarePolicies policies,
  }) {
    final last = <GarmentId, CleaningEvent>{};
    for (final c in cleanings) {
      final current = last[c.garmentId];
      if (current == null || _after(c.cleanedOn, c.createdAt, current)) {
        last[c.garmentId] = c;
      }
    }
    final uses = <GarmentId, int>{};
    for (final w in wears) {
      for (final id in w.garmentIds.toSet()) {
        final cleaned = last[id];
        if (cleaned == null || _after(w.wornOn, w.createdAt, cleaned)) {
          uses[id] = (uses[id] ?? 0) + 1;
        }
      }
    }
    return {
      for (final g in garments)
        g.id: LaundryState(
          usesSinceCleaning: uses[g.id] ?? 0,
          lastCleanedOn: last[g.id]?.cleanedOn,
          threshold: thresholdFor(g, policies),
        ),
    };
  }

  /// No mesmo dia, conta a ordem em que foram registados.
  static bool _after(CalendarDay day, DateTime created, CleaningEvent c) {
    final byDay = day.compareTo(c.cleanedOn);
    return byDay > 0 || (byDay == 0 && created.isAfter(c.createdAt));
  }
}

final class LaundryState {
  const LaundryState({
    required this.usesSinceCleaning,
    required this.threshold,
    this.lastCleanedOn,
  });

  /// Sem limpeza registada, conta todas as utilizações registadas (não se
  /// assume que a peça acabou de ser lavada).
  final int usesSinceCleaning;
  final CalendarDay? lastCleanedOn;

  /// `0` = sem aviso.
  final int threshold;

  bool get washRecommended => threshold > 0 && usesSinceCleaning >= threshold;
}
