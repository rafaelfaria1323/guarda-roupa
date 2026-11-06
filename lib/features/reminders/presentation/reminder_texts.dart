import '../../../l10n/app_localizations.dart';
import '../../engine/domain/suggestion.dart';
import '../../planner/application/plan_providers.dart';
import '../../planner/domain/plan_entry.dart';
import '../../wardrobe/domain/garment.dart';
import '../../wear/domain/calendar_day.dart';
import '../../wear/presentation/today_wear_card.dart' show garmentLabel;
import '../domain/reminder_backend.dart';

/// Os textos dos lembretes de cada dia planeado da semana, com os nomes das
/// peças e, para hoje e amanhã, os acessórios pelo tempo (a previsão de mais
/// longe muda muito). Dias já vestidos ou passados ficam de fora.
List<DaySummary> daySummaries({
  required AppLocalizations l10n,
  required CalendarDay today,
  required List<WeekDayView> week,
  required Map<CalendarDay, List<SuggestedItem>> accessories,
  required Map<GarmentId, Garment> garments,
}) {
  String names(Iterable<String> parts) => _cap(_joinAnd(l10n, parts.toList()));
  return [
    for (final d in week)
      if (d.entry case final entry?
          when entry.items.isNotEmpty &&
              d.state != PlanDayState.confirmed &&
              d.state != PlanDayState.unused)
        () {
          final outfit = names([
            for (final i in entry.items)
              garmentLabel(l10n, garments[i.garmentId]),
          ]);
          final extras = today.daysUntil(d.day) <= 1
              ? names([
                  for (final a in accessories[d.day] ?? const <SuggestedItem>[])
                    garmentLabel(l10n, a.garment),
                ])
              : '';
          return DaySummary(
            day: d.day,
            planVersion: entry.version,
            wearBody: l10n.reminderWearBody(outfit),
            eveBody: extras.isEmpty
                ? l10n.reminderEveBody(outfit)
                : l10n.reminderEveBodyExtras(outfit, extras),
          );
        }(),
  ];
}

String _joinAnd(AppLocalizations l10n, List<String> parts) => switch (parts) {
  [] => '',
  [final only] => only,
  _ => l10n.reminderListAnd(
    parts.sublist(0, parts.length - 1).join(', '),
    parts.last,
  ),
};

/// Os textos têm no máximo 300 caracteres na base; as peças ficam por 120.
String _cap(String s) => s.length <= 120 ? s : '${s.substring(0, 119)}…';
