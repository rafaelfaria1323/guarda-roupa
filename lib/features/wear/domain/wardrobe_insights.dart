import '../../wardrobe/domain/garment.dart';
import 'calendar_day.dart';
import 'wear_event.dart';

/// Uma peça e o seu uso, para o resumo do armário.
final class GarmentUse {
  const GarmentUse(this.garment, {required this.recentUses, this.lastWornOn});

  final Garment garment;

  /// Utilizações nos últimos [WardrobeInsights.recentDays] dias.
  final int recentUses;

  /// `null` = nunca usada (com "Vesti hoje").
  final CalendarDay? lastWornOn;
}

/// Resumo do armário (docs/features/utilizacao-e-rotatividade.md): o que
/// mais usas, o que está parado e o que nunca usaste. Só conta o uso
/// confirmado ("Vesti hoje"); peças arquivadas ficam de fora.
final class WardrobeInsights {
  const WardrobeInsights({
    required this.active,
    required this.wornRecently,
    required this.mostWorn,
    required this.idle,
    required this.neverWorn,
    required this.fresh,
    required this.hasHistory,
  });

  /// Janela de "ultimamente".
  static const recentDays = 30;

  /// Parada: a última vez foi há pelo menos isto.
  static const idleAfterDays = 60;

  /// Uma peça nova ainda não conta como "nunca usada".
  static const freshForDays = 14;

  /// Quantas peças em "Mais usadas".
  static const topCount = 5;

  factory WardrobeInsights.of(
    Iterable<Garment> garments,
    Iterable<WearEvent> wears,
    CalendarDay today,
  ) {
    final since = today.addDays(-(recentDays - 1));
    final last = <GarmentId, CalendarDay>{};
    final recent = <GarmentId, int>{};
    for (final w in wears) {
      if (w.wornOn.isAfter(today)) continue;
      for (final id in w.garmentIds.toSet()) {
        final l = last[id];
        if (l == null || w.wornOn.isAfter(l)) last[id] = w.wornOn;
        if (w.wornOn.compareTo(since) >= 0) recent[id] = (recent[id] ?? 0) + 1;
      }
    }
    final uses = [
      for (final g in garments)
        if (!g.isArchived)
          GarmentUse(g, recentUses: recent[g.id] ?? 0, lastWornOn: last[g.id]),
    ];
    int byId(GarmentUse a, GarmentUse b) =>
        a.garment.id.value.compareTo(b.garment.id.value);

    final most =
        [
          for (final u in uses)
            if (u.recentUses > 0) u,
        ]..sort((a, b) {
          final c = b.recentUses.compareTo(a.recentUses);
          if (c != 0) return c;
          final d = b.lastWornOn!.compareTo(a.lastWornOn!);
          return d != 0 ? d : byId(a, b);
        });
    final idle =
        [
          for (final u in uses)
            if (u.lastWornOn case final l?
                when l.daysUntil(today) >= idleAfterDays)
              u,
        ]..sort((a, b) {
          final c = a.lastWornOn!.compareTo(b.lastWornOn!);
          return c != 0 ? c : byId(a, b);
        });
    final unworn = [
      for (final u in uses)
        if (u.lastWornOn == null) u,
    ];
    bool isFresh(GarmentUse u) =>
        CalendarDay.of(u.garment.createdAt).daysUntil(today) < freshForDays;
    final never =
        [
          for (final u in unworn)
            if (!isFresh(u)) u,
        ]..sort((a, b) {
          final c = a.garment.createdAt.compareTo(b.garment.createdAt);
          return c != 0 ? c : byId(a, b);
        });

    return WardrobeInsights(
      active: uses.length,
      wornRecently: recent.keys
          .where((id) => uses.any((u) => u.garment.id == id))
          .length,
      mostWorn: most.take(topCount).toList(),
      idle: idle,
      neverWorn: never,
      fresh: unworn.where(isFresh).length,
      hasHistory: last.isNotEmpty,
    );
  }

  /// Peças não arquivadas.
  final int active;

  /// Peças (não arquivadas) usadas nos últimos [recentDays] dias.
  final int wornRecently;
  final List<GarmentUse> mostWorn;

  /// Usadas, mas não há [idleAfterDays] dias ou mais; as mais antigas
  /// primeiro.
  final List<GarmentUse> idle;

  /// Nunca usadas e no armário há [freshForDays] dias ou mais; as mais
  /// antigas primeiro.
  final List<GarmentUse> neverWorn;

  /// Nunca usadas, mas acabadas de chegar.
  final int fresh;

  /// Há pelo menos uma utilização registada.
  final bool hasHistory;
}
