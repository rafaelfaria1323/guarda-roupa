import '../../wardrobe/domain/garment.dart';
import '../../wardrobe/domain/garment_category.dart';
import '../../wear/domain/calendar_day.dart';
import '../../wear/domain/wear_event.dart';
import 'care_policies.dart';

/// Rotatividade (P-06): dias mínimos entre datas de utilização. Com 3, uma
/// utilização no dia 1 volta a ser elegível no dia 4. Conta dias de
/// calendário, não blocos de 24 h.
///
/// Sem alternativa elegível, sugere-se na mesma com aviso (não há modo
/// estrito). Disponibilidade, posse e arquivo nunca se flexibilizam aqui:
/// os candidatos já vêm filtrados.
abstract final class RotationPolicy {
  /// Valores aprovados em P-06. `0` = sem intervalo.
  static int defaultFor(GarmentCategory category) => switch (category.group) {
    CategoryGroup.top || CategoryGroup.onePiece => 3,
    CategoryGroup.bottom => 2,
    CategoryGroup.outerwear ||
    CategoryGroup.footwear ||
    CategoryGroup.accessory ||
    CategoryGroup.other => 0,
  };

  /// Peça > categoria > predefinido.
  static int daysFor(Garment garment, CarePolicies policies) =>
      policies.rotationByGarment[garment.id] ??
      policies.rotationByCategory[garment.category] ??
      defaultFor(garment.category);

  /// Janela usada para "menos usadas".
  static const recentWindowDays = 30;

  static Map<GarmentId, RotationState> evaluate({
    required Iterable<Garment> garments,
    required Iterable<WearEvent> wears,
    required CarePolicies policies,
    required CalendarDay today,
  }) {
    final last = <GarmentId, CalendarDay>{};
    final recent = <GarmentId, int>{};
    final windowStart = today.addDays(-recentWindowDays);
    for (final w in wears) {
      // Só o passado conta; reservas futuras não são utilizações.
      if (w.wornOn.isAfter(today)) continue;
      for (final id in w.garmentIds.toSet()) {
        final prev = last[id];
        if (prev == null || w.wornOn.isAfter(prev)) last[id] = w.wornOn;
        if (w.wornOn.isAfter(windowStart)) recent[id] = (recent[id] ?? 0) + 1;
      }
    }
    return {
      for (final g in garments)
        g.id: RotationState(
          days: daysFor(g, policies),
          lastWornOn: last[g.id],
          recentUses: recent[g.id] ?? 0,
          today: today,
        ),
    };
  }

  /// Ordena candidatos de um mesmo papel: elegíveis primeiro, depois menos
  /// usados nos últimos [recentWindowDays] dias, depois usados há mais tempo
  /// (nunca usados à frente). `id` desempata, para ser determinístico.
  static List<RotationChoice> rank(
    Iterable<Garment> candidates,
    Map<GarmentId, RotationState> states,
  ) {
    final choices = [
      for (final g in candidates)
        if (states[g.id] case final s?) RotationChoice(g, s),
    ];
    choices.sort((a, b) {
      final e = (b.state.isEligible ? 1 : 0) - (a.state.isEligible ? 1 : 0);
      if (e != 0) return e;
      final r = a.state.recentUses.compareTo(b.state.recentUses);
      if (r != 0) return r;
      final la = a.state.lastWornOn;
      final lb = b.state.lastWornOn;
      if (la != lb) {
        if (la == null) return -1;
        if (lb == null) return 1;
        final c = la.compareTo(lb);
        if (c != 0) return c;
      }
      return a.garment.id.value.compareTo(b.garment.id.value);
    });
    final anyEligible = choices.any((c) => c.state.isEligible);
    return [
      for (final c in choices)
        RotationChoice(c.garment, c.state, warning: !anyEligible),
    ];
  }
}

final class RotationState {
  const RotationState({
    required this.days,
    required this.recentUses,
    required this.today,
    this.lastWornOn,
  });

  /// `0` = sem intervalo.
  final int days;
  final CalendarDay? lastWornOn;
  final int recentUses;
  final CalendarDay today;

  /// Primeiro dia em que volta a ser elegível; `null` se já é (ou nunca
  /// foi usada, ou não tem intervalo).
  CalendarDay? get eligibleFrom {
    final last = lastWornOn;
    if (last == null || days == 0) return null;
    final from = last.addDays(days);
    return from.isAfter(today) ? from : null;
  }

  bool get isEligible => eligibleFrom == null;
}

/// Um candidato ordenado. [warning]: não havia nenhum elegível, por isso
/// esta sugestão ultrapassa o intervalo e tem de o dizer.
final class RotationChoice {
  const RotationChoice(this.garment, this.state, {this.warning = false});

  final Garment garment;
  final RotationState state;
  final bool warning;
}
