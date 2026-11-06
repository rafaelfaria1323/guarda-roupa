import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/domain/result.dart';
import '../../account_sync/application/providers.dart';
import '../../care/application/care_providers.dart';
import '../../engine/application/suggestion_providers.dart';
import '../../engine/domain/comfort.dart';
import '../../engine/domain/daily_engine.dart';
import '../../engine/domain/plan_review.dart';
import '../../engine/domain/suggestion.dart';
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

  /// Fica como está ao planear de novo: vestido, já passado ou deixado vazio.
  bool get keptOnReplan =>
      state == PlanDayState.confirmed ||
      state == PlanDayState.unused ||
      (state == PlanDayState.accepted && draft.items.isEmpty);
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
/// restantes recebem um conjunto novo, já aceite (semana sozinha, decisão
/// do utilizador a 2026-11-06). Nada disto conta como utilização.
///
/// Com [onlyEmpty] (o planeamento automático) só se enchem os dias sem
/// entrada; todos os outros contam como reserva, tal como estão. Sem ele
/// ("Planear de novo") refazem-se todos os dias ainda por vestir, menos os
/// que o utilizador deixou vazios.
Future<WeekGeneration> generateWeek(
  WidgetRef ref, {
  bool onlyEmpty = false,
}) async {
  final snapshot = ref.read(wardrobeSnapshotProvider);
  final view = ref.read(weekViewProvider);
  final repo = ref.read(planRepositoryProvider);
  if (snapshot == null || view == null || repo == null) {
    return const WeekNotReady();
  }
  // Tudo o que vem de `ref` lê-se antes de esperar: a app pode fechar
  // entretanto (o planeamento automático corre sozinho).
  final weatherFuture = ref.read(weekWeatherProvider.future);
  final comfortFuture = ref.read(comfortThresholdsProvider.future);
  final seed = ref.read(suggestionChoicesProvider).seed;
  final lastSearch = ref.read(lastWeekSearchProvider.notifier);
  // Sem previsão (offline, erro) planeia-se na mesma, sem regras de tempo.
  Map<CalendarDay, WeatherConditions> weather;
  try {
    weather = await weatherFuture;
  } on Object {
    weather = const {};
  }
  final comfort = await comfortFuture;
  final result = WeeklyPlanner.plan(
    snapshot,
    WeekRequest(
      days: [
        for (final d in view)
          if (onlyEmpty ? d.entry != null : d.keptOnReplan)
            WeekDayRequest(
              day: d.day,
              occasion: d.occasion,
              weather: weather[d.day],
              pinned: d.draft.items.isNotEmpty ? d.draft.items : null,
              include: d.draft.items.isNotEmpty,
            )
          else
            WeekDayRequest(
              day: d.day,
              occasion: d.occasion,
              weather: weather[d.day],
            ),
      ],
      comfort: comfort,
      seed: seed,
    ),
  );
  lastSearch.set(result);

  // A vista pode ainda não ter visto uma gravação recente: os dias vazios
  // confirmam-se na base antes de escrever.
  final taken = onlyEmpty
      ? {for (final e in await repo.watchDays(view.first.day).first) e.day}
      : const <CalendarDay>{};
  var proposed = 0;
  var notFound = 0;
  for (final (i, plan) in result.days.indexed) {
    final d = view[i];
    switch (plan.status) {
      case DayPlanStatus.planned when taken.contains(d.day):
        break;
      case DayPlanStatus.planned:
        final saved = await repo.saveDay(
          d.day,
          PlanDraft(
            occasion: d.occasion,
            tentative: d.tentative,
            items: plan.items,
            status: PlanStatus.accepted,
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

/// Liga a semana sozinha (`WeekAutopilot`). Os testes de outros fluxos
/// desligam-na, para não escreverem na base ao mesmo tempo que ela.
final weekAutopilotEnabledProvider = Provider<bool>((_) => true);

/// A semana está a ser planeada à mão ("Planear de novo"): a automática
/// espera.
final weekPlanningBusyProvider = NotifierProvider<WeekPlanningBusy, bool>(
  WeekPlanningBusy.new,
);

class WeekPlanningBusy extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) => state = value;
}

/// O que o planeamento automático já tentou nesta sessão: um dia sem
/// conjunto possível não se tenta outra vez até o guarda-roupa mudar.
final autoPlanAttemptsProvider =
    NotifierProvider<AutoPlanAttemptsNotifier, Set<String>>(
      AutoPlanAttemptsNotifier.new,
    );

class AutoPlanAttemptsNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  void add(String key) => state = {...state, key};
}

/// Há dias por planear e algo novo para tentar: devolve a chave da
/// tentativa (os dias vazios e as peças disponíveis), ou `null`.
final autoPlanKeyProvider = Provider<String?>((ref) {
  final snapshot = ref.watch(wardrobeSnapshotProvider);
  final view = ref.watch(weekViewProvider);
  if (snapshot == null || view == null) return null;
  final garments = [
    for (final g in snapshot.garments)
      if (g.isCandidate) g.id.value,
  ]..sort();
  if (garments.isEmpty) return null;
  final empty = [
    for (final d in view)
      if (d.entry == null) d.day.iso,
  ];
  if (empty.isEmpty) return null;
  final key = '${empty.join(',')}|${garments.join(',')}';
  return ref.watch(autoPlanAttemptsProvider).contains(key) ? null : key;
});

/// A previsão de cada dia da semana (da cache do repositório; um pedido
/// chega para a semana). Dias sem previsão ficam sem regras de conforto. O
/// tempo indicado à mão só vale para hoje.
final weekWeatherProvider = FutureProvider<Map<CalendarDay, WeatherConditions>>(
  (ref) async {
    final repo = ref.watch(weatherRepositoryProvider);
    final manual = ref.watch(suggestionChoicesProvider.select((c) => c.manual));
    final today = todayFrom(ref.watch(clockProvider));
    final location = await ref.watch(weatherLocationProvider.future);
    // Primeiro a de hoje: é ela que pede a previsão (um pedido chega para a
    // semana) e os outros dias leem a cache. Pedir de novo também chega aqui.
    await ref.watch(todayWeatherProvider.future);
    if (repo == null) return const {};
    final out = <CalendarDay, WeatherConditions>{};
    for (final day in WeekPlanRules.week(today)) {
      if (day == today && manual != null) {
        out[day] = manual.toConditions();
        continue;
      }
      if ((await repo.forDay(location, day)).weather case final w?) {
        out[day] = w.toConditions();
      }
    }
    return out;
  },
);

/// Acessórios que a previsão de cada dia planeado pede (chapéu-de-chuva,
/// cachecol, óculos de sol...). Não ficam no plano: seguem a previsão.
final weekAccessoriesProvider = Provider<Map<CalendarDay, List<SuggestedItem>>>(
  (ref) {
    final snapshot = ref.watch(wardrobeSnapshotProvider);
    final view = ref.watch(weekViewProvider);
    final weather = ref.watch(weekWeatherProvider).value;
    if (snapshot == null || view == null || weather == null) return const {};
    final comfort = currentComfort(ref);
    final seed = ref.watch(suggestionChoicesProvider.select((c) => c.seed));
    return {
      for (final d in view)
        if (d.draft.items.isNotEmpty &&
            d.state != PlanDayState.confirmed &&
            d.state != PlanDayState.unused)
          if (weather[d.day] case final w?)
            d.day: DailyEngine.accessories(
              snapshot,
              SuggestionRequest(
                day: d.day,
                occasion: d.occasion,
                weather: w,
                comfort: comfort,
                seed: seed,
              ),
            ),
    };
  },
);

/// Mudanças posteriores: dias planeados cujas peças deixaram de servir
/// (suja, arquivada, previsão, lavagem) e a substituição proposta. Quando há
/// peça para trocar, o ecrã aplica-a sozinho, com aviso e "Desfazer" (semana
/// sozinha, 2026-11-06). `null` enquanto carrega.
final weekReviewProvider = Provider<Map<CalendarDay, DayReview>?>((ref) {
  final snapshot = ref.watch(wardrobeSnapshotProvider);
  final view = ref.watch(weekViewProvider);
  if (snapshot == null || view == null) return null;
  // Sem previsão (ainda, ou de todo) revê-se o resto.
  final weather = ref.watch(weekWeatherProvider).value ?? const {};
  final reviews = PlanReview.review(
    snapshot,
    [
      for (final d in view)
        ReviewDay(
          day: d.day,
          items: d.entry?.items ?? const [],
          occasion: d.occasion,
          weather: weather[d.day],
          reviewable:
              d.state == PlanDayState.proposed ||
              d.state == PlanDayState.accepted,
        ),
    ],
    comfort: currentComfort(ref),
    seed: ref.watch(suggestionChoicesProvider.select((c) => c.seed)),
  );
  return {for (final r in reviews) r.day: r};
});

/// Substituições já tratadas nesta sessão (aplicadas sozinhas ou que o
/// utilizador decidiu não aplicar): os avisos ficam, a proposta deixa de
/// aparecer e não se volta a aplicar até mudar.
final ignoredDayChangesProvider =
    NotifierProvider<IgnoredDayChangesNotifier, Set<String>>(
      IgnoredDayChangesNotifier.new,
    );

class IgnoredDayChangesNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  void ignore(String key) => state = {...state, key};
}

/// Identifica uma proposta: o dia e as peças propostas.
String dayChangeKey(CalendarDay day, Replacement proposal) =>
    '${day.iso}:${[for (final i in proposal.items) i.garmentId.value].join(',')}';

/// Aplica a substituição proposta para o dia (confirmada pelo utilizador),
/// mantendo a ocasião e o estado.
Future<PlanResult<PlanEntry>?> applyDayChange(
  WidgetRef ref,
  WeekDayView day,
) async {
  final repo = ref.read(planRepositoryProvider);
  final proposal = ref.read(weekReviewProvider)?[day.day]?.proposal;
  if (repo == null || proposal == null) return null;
  final d = day.draft;
  return repo.saveDay(
    day.day,
    PlanDraft(
      occasion: d.occasion,
      tentative: d.tentative,
      items: proposal.items,
      status: d.status,
    ),
  );
}
