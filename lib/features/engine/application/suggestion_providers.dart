import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../account_sync/application/providers.dart';
import '../../care/application/care_providers.dart';
import '../../inspirations/application/inspiration_providers.dart';
import '../../outfits/application/outfit_providers.dart';
import '../../wardrobe/domain/garment_attributes.dart';
import '../../wear/application/wear_providers.dart';
import '../../weather/application/weather_providers.dart';
import '../../weather/domain/weather.dart';
import '../data/comfort_store.dart';
import '../domain/comfort.dart';
import '../domain/daily_engine.dart';
import '../domain/suggestion.dart';

/// Tudo o que o motor precisa; `null` enquanto carrega.
final wardrobeSnapshotProvider = Provider<WardrobeSnapshot?>((ref) {
  final garments = ref.watch(allGarmentsProvider).value;
  final wears = ref.watch(allWearsProvider).value;
  final cleanings = ref.watch(allCleaningsProvider).value;
  final policies = ref.watch(carePoliciesProvider).value;
  final preferences = ref.watch(preferencesProvider).value;
  final outfits = ref.watch(outfitsProvider).value;
  if (garments == null ||
      wears == null ||
      cleanings == null ||
      policies == null ||
      preferences == null ||
      outfits == null) {
    return null;
  }
  return WardrobeSnapshot(
    garments: garments,
    wears: wears,
    cleanings: cleanings,
    policies: policies,
    preferences: preferences,
    outfits: outfits,
  );
});

/// Previsão para hoje no local escolhido (com a cache do repositório).
final todayWeatherProvider = FutureProvider<WeatherReport?>((ref) async {
  final repo = ref.watch(weatherRepositoryProvider);
  final location = await ref.watch(weatherLocationProvider.future);
  if (repo == null) return null;
  return repo.forDay(location, todayFrom(ref.watch(clockProvider)));
});

/// Pede de novo a previsão, mesmo com cache recente.
Future<void> refreshTodayWeather(WidgetRef ref) async {
  final repo = ref.read(weatherRepositoryProvider);
  if (repo == null) return;
  final location = await ref.read(weatherLocationProvider.future);
  await repo.forDay(
    location,
    todayFrom(ref.read(clockProvider)),
    refresh: true,
  );
  ref.invalidate(todayWeatherProvider);
}

/// Contexto indicado à mão (docs/features/meteorologia.md): substitui a
/// previsão até ser retirado, e é sempre apresentado como manual.
final class ManualWeather {
  const ManualWeather(this.band, {this.rain = false});

  final ComfortBand band;
  final bool rain;

  /// Um valor representativo de cada faixa dos limites predefinidos.
  WeatherConditions toConditions() => WeatherConditions(
    feelsLikeC: switch (band) {
      ComfortBand.hot => 26,
      ComfortBand.mild => 18,
      ComfortBand.cold => 8,
    },
    rain: rain,
  );
}

/// Escolhas do utilizador para as sugestões de hoje (não persistem).
final class SuggestionChoices {
  const SuggestionChoices({this.occasion, this.manual, this.seed = 0});

  final Occasion? occasion;
  final ManualWeather? manual;
  final int seed;
}

final suggestionChoicesProvider =
    NotifierProvider<SuggestionChoicesNotifier, SuggestionChoices>(
      SuggestionChoicesNotifier.new,
    );

class SuggestionChoicesNotifier extends Notifier<SuggestionChoices> {
  @override
  SuggestionChoices build() => const SuggestionChoices();

  void occasion(Occasion? occasion) => state = SuggestionChoices(
    occasion: occasion,
    manual: state.manual,
    seed: state.seed,
  );

  void manual(ManualWeather? manual) => state = SuggestionChoices(
    occasion: state.occasion,
    manual: manual,
    seed: state.seed,
  );

  /// Outras escolhas entre peças equivalentes.
  void reshuffle() => state = SuggestionChoices(
    occasion: state.occasion,
    manual: state.manual,
    seed: state.seed + 1,
  );
}

final comfortStoreProvider = Provider<ComfortStore?>((ref) {
  final db = ref.watch(userDatabaseProvider).value;
  return db == null ? null : ComfortStore(db);
});

/// Limites de conforto (P-17), editáveis nas Definições; os de origem
/// enquanto não houver outros.
final comfortThresholdsProvider =
    AsyncNotifierProvider<ComfortThresholdsNotifier, ComfortThresholds>(
      ComfortThresholdsNotifier.new,
    );

class ComfortThresholdsNotifier extends AsyncNotifier<ComfortThresholds> {
  @override
  Future<ComfortThresholds> build() async {
    final store = ref.watch(comfortStoreProvider);
    return store == null ? const ComfortThresholds() : store.get();
  }

  Future<void> save(ComfortThresholds value) async {
    if (!value.isValid) return;
    final store = ref.read(comfortStoreProvider);
    if (store == null) return;
    await store.set(value);
    state = AsyncData(value);
  }
}

/// Os limites atuais, sem esperar: os de origem enquanto carregam.
ComfortThresholds currentComfort(Ref ref) =>
    ref.watch(comfortThresholdsProvider).value ?? const ComfortThresholds();

/// Sugestões de hoje; `null` enquanto o guarda-roupa carrega. Enquanto a
/// previsão carrega, sugere sem ela (e diz isso).
final todaySuggestionsProvider = Provider<SuggestionResult?>((ref) {
  final snapshot = ref.watch(wardrobeSnapshotProvider);
  if (snapshot == null) return null;
  return DailyEngine.suggest(snapshot, ref.watch(todayRequestProvider));
});

/// O pedido de hoje: dia, ocasião, tempo e limites de conforto (também o
/// que se manda ao stylist).
final todayRequestProvider = Provider<SuggestionRequest>((ref) {
  final choices = ref.watch(suggestionChoicesProvider);
  return SuggestionRequest(
    day: todayFrom(ref.watch(clockProvider)),
    occasion: choices.occasion,
    weather: ref.watch(todayConditionsProvider),
    comfort: currentComfort(ref),
    seed: choices.seed,
  );
});

/// O tempo das sugestões de hoje: o indicado à mão ou a previsão (`null`
/// enquanto carrega ou sem nenhum dos dois).
final todayConditionsProvider = Provider<WeatherConditions?>((ref) {
  final manual = ref.watch(suggestionChoicesProvider).manual;
  if (manual != null) return manual.toConditions();
  return ref.watch(todayWeatherProvider).value?.weather?.toConditions();
});
