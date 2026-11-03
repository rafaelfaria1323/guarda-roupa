import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../account_sync/application/providers.dart';
import '../../wear/application/wear_providers.dart';
import '../data/open_meteo_client.dart';
import '../data/weather_repository.dart';
import '../domain/weather.dart';

/// Substituído nos testes (`MockClient`): os testes nunca vão à rede.
final httpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

final openMeteoClientProvider = Provider<OpenMeteoClient>(
  (ref) => OpenMeteoClient(ref.watch(httpClientProvider)),
);

final weatherLocationStoreProvider = Provider<WeatherLocationStore?>((ref) {
  final db = ref.watch(userDatabaseProvider).value;
  return db == null ? null : WeatherLocationStore(db);
});

/// Local escolhido (P-18); Torres Vedras enquanto não houver outro.
final weatherLocationProvider =
    AsyncNotifierProvider<WeatherLocationNotifier, WeatherLocation>(
      WeatherLocationNotifier.new,
    );

class WeatherLocationNotifier extends AsyncNotifier<WeatherLocation> {
  @override
  Future<WeatherLocation> build() async {
    final store = ref.watch(weatherLocationStoreProvider);
    return store == null ? WeatherLocation.torresVedras : store.get();
  }

  Future<void> choose(WeatherLocation location) async {
    final store = ref.read(weatherLocationStoreProvider);
    if (store == null) return;
    await store.set(location);
    state = AsyncData(location.rounded());
  }
}

final weatherRepositoryProvider = Provider<WeatherRepository?>((ref) {
  final db = ref.watch(userDatabaseProvider).value;
  if (db == null) return null;
  return WeatherRepository(
    db: db,
    client: ref.watch(openMeteoClientProvider),
    clock: ref.watch(clockProvider),
  );
});
