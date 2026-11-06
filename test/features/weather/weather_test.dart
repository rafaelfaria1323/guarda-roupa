import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:guarda_roupa/features/weather/data/open_meteo_client.dart';
import 'package:guarda_roupa/features/weather/data/weather_repository.dart';
import 'package:guarda_roupa/features/weather/domain/weather.dart';
import 'package:guarda_roupa/features/wear/domain/calendar_day.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:powersync/powersync.dart';

import '../../support/test_database.dart';
import '../wardrobe/domain/fakes.dart';

/// Resposta horária do Open-Meteo para [days] dias a partir de 3/11.
/// [feels] dá a sensação para (dia, hora).
Map<String, Object?> hourly({
  int days = 2,
  double Function(int day, int hour)? feels,
  double Function(int day, int hour)? rain,
  double wind = 10,
  int? probability = 10,
  double Function(int day, int hour)? uv,
}) {
  final time = <String>[];
  final f = <double?>[];
  final r = <double?>[];
  final w = <double?>[];
  final p = <int?>[];
  final u = <double?>[];
  for (var d = 0; d < days; d++) {
    final day = CalendarDay(2026, 11, 3).addDays(d).iso;
    for (var h = 0; h < 24; h++) {
      time.add('${day}T${h.toString().padLeft(2, '0')}:00');
      f.add(feels?.call(d, h) ?? 15);
      r.add(rain?.call(d, h) ?? 0);
      w.add(wind);
      p.add(probability);
      u.add(uv?.call(d, h) ?? 0);
    }
  }
  return {
    'hourly': {
      'time': time,
      'apparent_temperature': f,
      'precipitation': r,
      'precipitation_probability': p,
      'wind_speed_10m': w,
      if (uv != null) 'uv_index': u,
    },
  };
}

void main() {
  group('Open-Meteo', () {
    test('o pedido leva só coordenadas arredondadas e o fuso', () {
      final uri = OpenMeteoClient.forecastUri(
        const WeatherLocation(
          name: 'X',
          latitude: 39.091234,
          longitude: -9.258765,
          timezone: 'Europe/Lisbon',
        ),
      );
      expect(uri.host, 'api.open-meteo.com');
      expect(uri.queryParameters['latitude'], '39.09');
      expect(uri.queryParameters['longitude'], '-9.26');
      expect(uri.queryParameters['timezone'], 'Europe/Lisbon');
      expect(uri.queryParameters['forecast_days'], '7');
    });

    test('resume cada dia nas horas das 8 às 20', () {
      final days = OpenMeteoClient.parseForecast(
        hourly(
          // Madrugada gelada não conta.
          feels: (d, h) => h < 8 ? -5 : (d == 0 ? 20 : 10) + (h == 14 ? 6 : 0),
          rain: (d, h) => d == 1 && h == 12 ? 0.6 : (h == 3 ? 9 : 0),
          probability: 30,
        ),
      );
      expect(days.map((d) => d.day.iso), ['2026-11-03', '2026-11-04']);
      final first = days.first;
      expect(first.feelsLikeC, closeTo(20 + 6 / 13, 1e-9));
      expect(first.feelsLikeMinC, 20);
      expect(first.feelsLikeMaxC, 26);
      expect(first.precipitationMm, 0);
      expect(first.precipitationProbability, 30);
      expect(days[1].precipitationMm, closeTo(0.6, 1e-9));
    });

    test('UV: máximo nas horas do dia; sem coluna fica por saber', () {
      final days = OpenMeteoClient.parseForecast(
        hourly(uv: (d, h) => h == 13 ? (d == 0 ? 5.5 : 1) : (h == 2 ? 9 : 0)),
      );
      expect(days.map((d) => d.uvIndexMax), [5.5, 1]);
      expect(OpenMeteoClient.parseForecast(hourly()).first.uvIndexMax, isNull);
      expect(DayWeather.fromJson(days.first.toJson())!.uvIndexMax, 5.5);
    });

    test('sol: UV ≥ 3 e sem chuva', () {
      DayWeather d({double? uv, double mm = 0}) => DayWeather(
        day: CalendarDay(2026, 11, 3),
        feelsLikeC: 20,
        feelsLikeMinC: 20,
        feelsLikeMaxC: 20,
        precipitationMm: mm,
        windMaxKmh: 0,
        uvIndexMax: uv,
      );
      expect(d(uv: 3).toConditions().sunny, isTrue);
      expect(d(uv: 2.9).toConditions().sunny, isFalse);
      expect(d(uv: 6, mm: 4).toConditions().sunny, isFalse);
      expect(d().toConditions().sunny, isFalse);
    });

    test('dia incompleto ou com valores em falta fica de fora', () {
      final json = hourly(days: 2);
      final h = json['hourly']! as Map<String, Object?>;
      (h['apparent_temperature']! as List)[24 + 10] = null;
      final days = OpenMeteoClient.parseForecast(json);
      expect(days.map((d) => d.day.iso), ['2026-11-03']);
    });

    test('resposta inválida falha com WeatherFetchFailed', () {
      expect(
        () => OpenMeteoClient.parseForecast({'nope': 1}),
        throwsA(isA<WeatherFetchFailed>()),
      );
    });

    test('chuva: ≥ 1 mm ou probabilidade ≥ 50 %', () {
      DayWeather d({double mm = 0, int? p}) => DayWeather(
        day: CalendarDay(2026, 11, 3),
        feelsLikeC: 15,
        feelsLikeMinC: 15,
        feelsLikeMaxC: 15,
        precipitationMm: mm,
        windMaxKmh: 0,
        precipitationProbability: p,
      );
      expect(RainRule.isRainy(d(mm: 1)), isTrue);
      expect(RainRule.isRainy(d(mm: 0.9, p: 49)), isFalse);
      expect(RainRule.isRainy(d(p: 50)), isTrue);
      expect(RainRule.isRainy(d()), isFalse);
      final c = d(mm: 2).toConditions();
      expect((c.feelsLikeC, c.rain), (15, true));
    });

    test('pesquisa por nome devolve localidades arredondadas', () async {
      final client = OpenMeteoClient(
        MockClient((req) async {
          expect(req.url.host, 'geocoding-api.open-meteo.com');
          expect(req.url.queryParameters['name'], 'Lisboa');
          return http.Response(
            jsonEncode({
              'results': [
                {
                  'name': 'Lisboa',
                  'admin1': 'Lisboa',
                  'latitude': 38.71667,
                  'longitude': -9.13333,
                  'timezone': 'Europe/Lisbon',
                },
                {'name': 'Sem coordenadas', 'timezone': 'Europe/Lisbon'},
              ],
            }),
            200,
          );
        }),
      );
      final found = await client.search(' Lisboa ');
      expect(found, hasLength(1));
      expect((found.single.latitude, found.single.longitude), (38.72, -9.13));
      expect(await client.search('L'), isEmpty);
    });

    test('erro de rede ou HTTP vira WeatherFetchFailed', () async {
      final down = OpenMeteoClient(
        MockClient((_) async => throw http.ClientException('offline')),
      );
      await expectLater(
        down.forecast(WeatherLocation.torresVedras),
        throwsA(isA<WeatherFetchFailed>()),
      );
      final error = OpenMeteoClient(
        MockClient((_) async => http.Response('limit', 429)),
      );
      await expectLater(
        error.search('Lisboa'),
        throwsA(isA<WeatherFetchFailed>()),
      );
    });
  });

  group('WeatherRepository', () {
    late int calls;
    late bool online;
    late FixedClock clock;

    WeatherRepository repo(PowerSyncDatabase db) => WeatherRepository(
      db: db,
      clock: clock,
      client: OpenMeteoClient(
        MockClient((req) async {
          calls++;
          if (!online) throw http.ClientException('offline');
          return http.Response(
            jsonEncode(hourly(days: 7, feels: (d, _) => 10.0 + d)),
            200,
          );
        }),
      ),
    );

    setUp(() {
      calls = 0;
      online = true;
      clock = FixedClock(DateTime.utc(2026, 11, 3, 9));
    });

    test('pede uma vez e usa a cache durante 3 h', () async {
      final r = repo(await openTestDatabase());
      const loc = WeatherLocation.torresVedras;
      final today = CalendarDay(2026, 11, 3);
      final a = await r.forDay(loc, today);
      expect(a.weather?.feelsLikeC, 10);
      expect(a.freshness, ForecastFreshness.fresh);
      await r.forDay(loc, today.addDays(1));
      expect(calls, 1);

      clock.now = clock.now.add(const Duration(hours: 3));
      await r.forDay(loc, today);
      expect(calls, 2);

      await r.forDay(loc, today, refresh: true);
      expect(calls, 3);
    });

    test('sem rede usa a cópia guardada e diz que é antiga', () async {
      final r = repo(await openTestDatabase());
      const loc = WeatherLocation.torresVedras;
      final today = CalendarDay(2026, 11, 3);
      await r.forDay(loc, today);

      online = false;
      clock.now = clock.now.add(const Duration(hours: 4));
      final recent = await r.forDay(loc, today);
      expect(recent.freshness, ForecastFreshness.fresh);
      expect(recent.fetchedAt, DateTime.utc(2026, 11, 3, 9));

      clock.now = clock.now.add(const Duration(hours: 3));
      final old = await r.forDay(loc, today);
      expect(old.freshness, ForecastFreshness.stale);
      expect(old.weather?.feelsLikeC, 10);
    });

    test('sem rede e sem cache: ausente, nunca inventada', () async {
      online = false;
      final r = repo(await openTestDatabase());
      final report = await r.forDay(
        WeatherLocation.torresVedras,
        CalendarDay(2026, 11, 3),
      );
      expect(report.weather, isNull);
      expect(report.gap, ForecastGap.unavailable);
    });

    test('fora do horizonte: ausente', () async {
      final r = repo(await openTestDatabase());
      final report = await r.forDay(
        WeatherLocation.torresVedras,
        CalendarDay(2026, 11, 20),
      );
      expect(report.gap, ForecastGap.outOfRange);
    });

    test('mudar de local não reaproveita a previsão de outro', () async {
      final r = repo(await openTestDatabase());
      final today = CalendarDay(2026, 11, 3);
      await r.forDay(WeatherLocation.torresVedras, today);
      online = false;
      final other = await r.forDay(
        const WeatherLocation(
          name: 'Porto',
          latitude: 41.15,
          longitude: -8.61,
          timezone: 'Europe/Lisbon',
        ),
        today,
      );
      expect(other.gap, ForecastGap.unavailable);
    });
  });

  group('WeatherLocationStore', () {
    test('Torres Vedras por omissão; guarda o escolhido', () async {
      final store = WeatherLocationStore(await openTestDatabase());
      expect(await store.get(), WeatherLocation.torresVedras);
      const porto = WeatherLocation(
        name: 'Porto',
        region: 'Porto',
        latitude: 41.149612,
        longitude: -8.610998,
        timezone: 'Europe/Lisbon',
      );
      await store.set(porto);
      final got = await store.get();
      expect(got.name, 'Porto');
      expect((got.latitude, got.longitude), (41.15, -8.61));
      expect(got.region, 'Porto');
    });
  });
}
