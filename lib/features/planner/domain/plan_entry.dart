import '../../outfits/domain/outfit.dart';
import '../../wardrobe/domain/garment_attributes.dart';
import '../../wear/domain/calendar_day.dart';

/// Estado guardado de uma entrada (o servidor só conhece estes dois).
enum PlanStatus {
  /// Sugerido (pelo motor ou ainda por rever).
  proposed('proposed'),

  /// Aceite pelo utilizador.
  accepted('accepted');

  const PlanStatus(this.id);
  final String id;

  static PlanStatus? fromId(String? id) {
    for (final s in values) {
      if (s.id == id) return s;
    }
    return null;
  }
}

/// Estado de um dia, como o utilizador o vê. "Confirmada" e "não utilizada"
/// não se guardam: vêm das utilizações (`plan_entry_id`) e da data.
enum PlanDayState { proposed, accepted, confirmed, unused }

/// Alterações que chegaram com uma versão desatualizada (ADR-008) e esperam
/// que o utilizador as aceite ou rejeite. Só os campos presentes mudariam.
final class PlanProposal {
  const PlanProposal({
    this.changesOccasion = false,
    this.occasion,
    this.tentative,
    this.items,
    this.status,
  });

  final bool changesOccasion;
  final Occasion? occasion;
  final bool? tentative;
  final List<OutfitItem>? items;
  final PlanStatus? status;
}

/// O plano de um dia. Nunca é uma utilização: só "Vesti hoje" conta (P-08).
final class PlanEntry {
  const PlanEntry({
    required this.id,
    required this.day,
    required this.items,
    required this.status,
    required this.version,
    required this.createdAt,
    required this.updatedAt,
    this.occasion,
    this.tentative = false,
    this.proposal,
  });

  final String id;
  final CalendarDay day;

  /// `null` = "a decidir".
  final Occasion? occasion;

  /// Pode não acontecer nada que peça esta roupa (fim de semana, P-19).
  final bool tentative;

  /// Pela ordem das camadas; vazio num dia provisório ainda por planear.
  final List<OutfitItem> items;
  final PlanStatus status;
  final int version;
  final PlanProposal? proposal;
  final DateTime createdAt;
  final DateTime updatedAt;

  PlanDraft toDraft() => PlanDraft(
    occasion: occasion,
    tentative: tentative,
    items: items,
    status: status,
  );

  /// [confirmed]: há uma utilização ativa com este `plan_entry_id`.
  PlanDayState stateOn(CalendarDay today, {required bool confirmed}) {
    if (confirmed) return PlanDayState.confirmed;
    if (today.isAfter(day)) return PlanDayState.unused;
    return status == PlanStatus.accepted
        ? PlanDayState.accepted
        : PlanDayState.proposed;
  }
}

final class PlanDraft {
  const PlanDraft({
    this.occasion,
    this.tentative = false,
    this.items = const [],
    this.status = PlanStatus.proposed,
  });

  final Occasion? occasion;
  final bool tentative;
  final List<OutfitItem> items;
  final PlanStatus status;

  /// O ponto de partida de um dia por planear (P-19).
  factory PlanDraft.defaultFor(CalendarDay day) => PlanDraft(
    occasion: WeekPlanRules.defaultOccasion(day),
    tentative: WeekPlanRules.tentativeByDefault(day),
  );
}

enum PlanProblem { tooManyItems, duplicateGarment, roleTaken }

/// Regras da semana (P-19, docs/features/planeamento-semanal.md).
abstract final class WeekPlanRules {
  static const days = 7;

  /// Os 7 dias a partir de [from] (inclusive).
  static List<CalendarDay> week(CalendarDay from) => [
    for (var i = 0; i < days; i++) from.addDays(i),
  ];

  /// Dias úteis: trabalho (smart casual). Fim de semana: a decidir.
  static Occasion? defaultOccasion(CalendarDay day) =>
      day.isWeekend ? null : Occasion.workCasual;

  /// O fim de semana é provisório: pode não acontecer nada que peça roupa
  /// planeada, e o dia pode ficar vazio.
  static bool tentativeByDefault(CalendarDay day) => day.isWeekend;

  /// Como os conjuntos, mas sem peças também é válido.
  static PlanProblem? validate(PlanDraft draft) {
    if (draft.items.isEmpty) return null;
    return switch (OutfitRules.validate(OutfitDraft(items: draft.items))) {
      null || OutfitProblem.noItems || OutfitProblem.nameTooLong => null,
      OutfitProblem.tooManyItems => PlanProblem.tooManyItems,
      OutfitProblem.duplicateGarment => PlanProblem.duplicateGarment,
      OutfitProblem.roleTaken => PlanProblem.roleTaken,
    };
  }
}
