import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/domain/result.dart';
import '../../account_sync/application/providers.dart';
import '../../care/application/care_providers.dart';
import '../../engine/application/suggestion_providers.dart';
import '../../engine/domain/comfort.dart';
import '../../engine/domain/weekly_planner.dart';
import '../../wardrobe/domain/garment_attributes.dart';
import '../../wear/application/wear_providers.dart';
import '../../wear/domain/calendar_day.dart';
import '../../wear/domain/wear_event.dart';
import '../../weather/application/weather_providers.dart';
import '../../weather/domain/weather.dart';
import '../data/powersync_plan_repository.dart';
import '../domain/plan_entry.dart';
import '../domain/plan_repository.dart';

final planRepositoryProvider = Provider<PlanRepository?>((ref) {
  final user = ref.watch(currentUserProvider).value;
  final db = ref.watch(userDatabaseProvider).value;
  if (user == null || db == null) return null;
  return PowerSyncPlanRepository(
    db: db,
    ownerId: user.id,
    clock: ref.watch(clockProvider),
  );
});

/// As entradas dos 7 dias a partir de [from] (dias sem entrada ficam de
/// fora: o ponto de partida é `PlanDraft.defaultFor`).
final weekPlanProvider = StreamProvider.family<List<PlanEntry>, CalendarDay>((
  ref,
  from,
) {
  final repo = ref.watch(planRepositoryProvider);
  return repo == null
      ? const Stream.empty()
      : repo.watchDays(from, days: WeekPlanRules.days);
});

/// Um dia da semana como o ecrã o mostra.
final class WeekDayView {
  const WeekDayView({
    required this.day,
    required this.state,
    this.entry,
    this.wear,
  });

  final CalendarDay day;
  final PlanEntry? entry;

  /// Utilização que confirmou esta entrada ("Vesti hoje" a partir do plano).
  final WearEvent? wear;

  /// `null` = sem entrada.
  final PlanDayState? state;

  Occasion? get occasion =>
      entry == null ? WeekPlanRules.defaultOccasion(day) : entry!.occasion;
  bool get tentative =>
      entry?.tentative ?? WeekPlanRules.tentativeByDefault(day);

  /// O ponto de partida para editar este dia.
  PlanDraft get draft => entry?.toDraft() ?? PlanDraft.defaultFor(day);

  /// Fica como está ao planear a semana: aceite, confirmado ou já passado.
  bool get kept =>
      state == PlanDayState.accepted ||
      state == PlanDayState.confirmed ||
      state == PlanDayState.unused;
}

/// Os 7 dias a partir de hoje; `null` enquanto carrega.
final weekViewProvider = Provider<List<WeekDayView>?>((ref) {
  final today = todayFrom(ref.watch(clockProvider));
  final entries = ref.watch(weekPlanProvider(today)).value;
  final wears = ref.watch(allWearsProvider).value;
  if (entries == null || wears == null) return null;
  final byDay = {for (final e in entries) e.day: e};
  final byEntry = {
    for (final w in wears)
      if (w.planEntryId != null) w.planEntryId!: w,
  };
  return [
    for (final day in WeekPlanRules.week(today))
      if (byDay[day] case final entry?)
        WeekDayView(
          day: day,
          entry: entry,
          wear: byEntry[entry.id],
          state: entry.stateOn(today, confirmed: byEntry[entry.id] != null),
        )
      else
        WeekDayView(day: day, state: null),
  ];
});

/// O último resultado da pesquisa semanal (não persiste): repetições e dias
/// sem conjunto possível, para explicar a semana proposta.
final lastWeekSearchProvider =
    NotifierProvider<LastWeekSearchNotifier, WeekPlanResult?>(
      LastWeekSearchNotifier.new,
    );

class LastWeekSearchNotifier extends Notifier<WeekPlanResult?> {
  @override
  WeekPlanResult? build() => null;

  void set(WeekPlanResult? result) => state = result;
}

sealed class WeekGeneration {
  const WeekGeneration();
}

/// O guarda-roupa ou o plano ainda estão a carregar.
final class WeekNotReady extends WeekGeneration {
  const WeekNotReady();
}

final class WeekGenerated extends WeekGeneration {
  const WeekGenerated({required this.proposed, required this.notFound});
  final int proposed;
  final int notFound;
}

final class WeekSaveFailed extends WeekGeneration {
  const WeekSaveFailed(this.failure);
  final PlanFailure failure;
}

/// Planeia a semana (P-19): os dias aceites, confirmados ou passados ficam
/// como estão (contam como reserva); um dia aceite vazio fica de fora; os
/// restantes recebem uma proposta nova. Nada disto conta como utilização.
Future<WeekGeneration> generateWeek(WidgetRef ref) async {
  final snapshot = ref.read(wardrobeSnapshotProvider);
  final view = ref.read(weekViewProvider);
  final repo = ref.read(planRepositoryProvider);
  if (snapshot == null || view == null || repo == null) {
    return const WeekNotReady();
  }
  final weather = await _weekWeather(ref, [for (final d in view) d.day]);
  final result = WeeklyPlanner.plan(
    snapshot,
    WeekRequest(
      days: [
        for (final d in view)
          WeekDayRequest(
            day: d.day,
            occasion: d.occasion,
            weather: weather[d.day],
            pinned: d.kept && d.draft.items.isNotEmpty ? d.draft.items : null,
            include: !(d.kept && d.draft.items.isEmpty),
          ),
      ],
      seed: ref.read(suggestionChoicesProvider).seed,
    ),
  );
  ref.read(lastWeekSearchProvider.notifier).set(result);

  var proposed = 0;
  var notFound = 0;
  for (final (i, plan) in result.days.indexed) {
    final d = view[i];
    switch (plan.status) {
      case DayPlanStatus.planned:
        final saved = await repo.saveDay(
          d.day,
          PlanDraft(
            occasion: d.occasion,
            tentative: d.tentative,
            items: plan.items,
          ),
        );
        if (saved case Err(:final failure)) return WeekSaveFailed(failure);
        proposed++;
      case DayPlanStatus.notFound:
        notFound++;
      case DayPlanStatus.pinned || DayPlanStatus.skipped:
        break;
    }
  }
  return WeekGenerated(proposed: proposed, notFound: notFound);
}

/// A previsão de cada dia (da cache do repositório; um pedido chega para a
/// semana). Dias sem previsão ficam sem regras de conforto, como hoje.
Future<Map<CalendarDay, WeatherConditions>> _weekWeather(
  WidgetRef ref,
  List<CalendarDay> days,
) async {
  final repo = ref.read(weatherRepositoryProvider);
  if (repo == null) return const {};
  final location = await ref.read(weatherLocationProvider.future);
  final manual = ref.read(suggestionChoicesProvider).manual;
  final today = todayFrom(ref.read(clockProvider));
  final out = <CalendarDay, WeatherConditions>{};
  for (final day in days) {
    // O tempo indicado à mão só vale para hoje.
    if (day == today && manual != null) {
      out[day] = manual.toConditions();
      continue;
    }
    if ((await repo.forDay(location, day)).weather case final w?) {
      out[day] = w.toConditions();
    }
  }
  return out;
}
