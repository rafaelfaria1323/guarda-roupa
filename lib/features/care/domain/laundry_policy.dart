import '../../wardrobe/domain/garment.dart';
import '../../wardrobe/domain/garment_attributes.dart';
import '../../wardrobe/domain/garment_category.dart';
import '../../wardrobe/domain/garment_filter.dart';
import '../../wear/domain/calendar_day.dart';
import '../../wear/domain/wear_event.dart';
import 'care_policies.dart';
import 'cleaning_event.dart';

/// Recomendação de lavagem (P-07): conta as utilizações confirmadas desde
/// a última limpeza registada. Ao confirmar uma utilização que chega ao
/// limiar, a peça passa sozinha a "Precisa de limpeza" ([dirtyAfterWear],
/// decisão do utilizador a 2026-11-06); só volta a disponível quando o
/// utilizador regista "Lavei hoje" ou a muda à mão.
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
    GarmentCategory.scarf ||
    GarmentCategory.beanie ||
    GarmentCategory.gloves ||
    GarmentCategory.hat ||
    GarmentCategory.sunglasses ||
    GarmentCategory.umbrella ||
    GarmentCategory.belt ||
    GarmentCategory.bag ||
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

  /// As peças de [event] que, com ele, chegam ao limiar de lavagem e ainda
  /// estão disponíveis: passam a "Precisa de limpeza". [wears] pode já
  /// conter [event] (conta uma vez).
  static List<GarmentId> dirtyAfterWear(
    WearEvent event, {
    required Iterable<Garment> garments,
    required Iterable<WearEvent> wears,
    required Iterable<CleaningEvent> cleanings,
    required CarePolicies policies,
  }) {
    final worn = event.garmentIds.toSet();
    final candidates = [
      for (final g in garments)
        if (worn.contains(g.id) && g.isCandidate) g,
    ];
    final states = evaluate(
      garments: candidates,
      wears: [
        for (final w in wears)
          if (w.id != event.id) w,
        event,
      ],
      cleanings: cleanings,
      policies: policies,
    );
    return [
      for (final g in candidates)
        if (states[g.id]!.washRecommended) g.id,
    ];
  }

  /// A peça vai à lavandaria: a lavagem indicada é "limpeza profissional"
  /// ou, sem ela, o texto da etiqueta pede-o ([asksProfessional]).
  static bool isProfessional(GarmentAttributes a) => switch (a.wash) {
    WashCare.professional => true,
    null => asksProfessional(a.care),
    _ => false,
  };

  /// O texto de cuidados da etiqueta pede limpeza profissional (a seco ou
  /// "não lavar"). Só se lê o que o utilizador escreveu; nada se adivinha.
  static bool asksProfessional(String? care) {
    if (care == null) return false;
    final text = GarmentFilter.fold(care);
    return _professional.any(text.contains);
  }

  static const _professional = [
    'a seco',
    'limpeza profissional',
    'lavandaria',
    'nao lavar',
    'dry clean',
    'professional',
    'do not wash',
  ];

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
