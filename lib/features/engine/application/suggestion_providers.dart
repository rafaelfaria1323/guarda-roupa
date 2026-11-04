import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../care/application/care_providers.dart';
import '../../inspirations/application/inspiration_providers.dart';
import '../../wardrobe/domain/garment_attributes.dart';
import '../../wear/application/wear_providers.dart';
import '../../weather/application/weather_providers.dart';
import '../../weather/domain/weather.dart';
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
  if (garments == null ||
      wears == null ||
      cleanings == null ||
      policies == null ||
      preferences == null) {
    return null;
  }
  return WardrobeSnapshot(
    garments: garments,
    wears: wears,
    cleanings: cleanings,
    policies: policies,
    preferences: preferences,
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

/// Sugestões de hoje; `null` enquanto o guarda-roupa carrega. Enquanto a
/// previsão carrega, sugere sem ela (e diz isso).
final todaySuggestionsProvider = Provider<SuggestionResult?>((ref) {
  final snapshot = ref.watch(wardrobeSnapshotProvider);
  if (snapshot == null) return null;
  final choices = ref.watch(suggestionChoicesProvider);
  final report = ref.watch(todayWeatherProvider).value;
  final conditions =
      choices.manual?.toConditions() ?? report?.weather?.toConditions();
  return DailyEngine.suggest(
    snapshot,
    SuggestionRequest(
      day: todayFrom(ref.watch(clockProvider)),
      occasion: choices.occasion,
      weather: conditions,
      seed: choices.seed,
    ),
  );
});
