import 'dart:convert';

import 'package:sqlite_async/sqlite_async.dart';

import '../../../core/domain/clock.dart';
import '../../wear/domain/calendar_day.dart';
import '../domain/weather.dart';
import 'open_meteo_client.dart';

/// Tabelas locais (fora do schema sincronizado): a previsão é deste
/// dispositivo e o local escolhido também.
abstract final class WeatherTables {
  static const create = [
    'CREATE TABLE IF NOT EXISTS weather_cache ('
        'location_key TEXT PRIMARY KEY NOT NULL, fetched_at TEXT NOT NULL, '
        'days TEXT NOT NULL)',
    'CREATE TABLE IF NOT EXISTS local_settings ('
        'key TEXT PRIMARY KEY NOT NULL, value TEXT NOT NULL)',
  ];
}

/// Local escolhido para a previsão (P-18). Sem escolha, Torres Vedras.
final class WeatherLocationStore {
  WeatherLocationStore(this._db);

  final SqliteConnection _db;
  static const _key = 'weather_location';

  Future<WeatherLocation> get() async {
    final row = await _db.getOptional(
      'SELECT value FROM local_settings WHERE key = ?',
      [_key],
    );
    final value = row?['value'];
    if (value is! String) return WeatherLocation.torresVedras;
    try {
      return WeatherLocation.fromJson(jsonDecode(value)) ??
          WeatherLocation.torresVedras;
    } on FormatException {
      return WeatherLocation.torresVedras;
    }
  }

  Future<void> set(WeatherLocation location) => _db.execute(
    'INSERT OR REPLACE INTO local_settings (key, value) VALUES (?, ?)',
    [_key, jsonEncode(location.rounded().toJson())],
  );
}

/// Previsão com cache por local (docs/features/meteorologia.md): pede ao
/// Open-Meteo no máximo uma vez por [refreshAfter]; sem rede usa a cópia
/// guardada e diz que é antiga.
final class WeatherRepository {
  WeatherRepository({
    required this._db,
    required this._client,
    required this._clock,
  });

  final SqliteConnection _db;
  final OpenMeteoClient _client;
  final Clock _clock;

  static const refreshAfter = Duration(hours: 3);

  /// [refresh] força um pedido (ex.: "atualizar"), mesmo com cache recente.
  Future<WeatherReport> forDay(
    WeatherLocation location,
    CalendarDay day, {
    bool refresh = false,
  }) async {
    final now = _clock.nowUtc();
    var cached = await _read(location);
    if (refresh ||
        cached == null ||
        now.difference(cached.fetchedAt) >= refreshAfter) {
      try {
        final days = await _client.forecast(location);
        await _write(location, now, days);
        cached = (fetchedAt: now, days: days);
      } on WeatherFetchFailed {
        // Fica a cópia guardada (se houver), marcada como antiga.
      }
    }
    if (cached == null) {
      return WeatherReport.missing(ForecastGap.unavailable, location: location);
    }
    for (final d in cached.days) {
      if (d.day == day) {
        return WeatherReport.forecast(
          weather: d,
          fetchedAt: cached.fetchedAt,
          freshness: now.difference(cached.fetchedAt) <= WeatherReport.freshFor
              ? ForecastFreshness.fresh
              : ForecastFreshness.stale,
          location: location,
        );
      }
    }
    return WeatherReport.missing(ForecastGap.outOfRange, location: location);
  }

  Future<({DateTime fetchedAt, List<DayWeather> days})?> _read(
    WeatherLocation location,
  ) async {
    final row = await _db.getOptional(
      'SELECT fetched_at, days FROM weather_cache WHERE location_key = ?',
      [location.cacheKey],
    );
    if (row == null) return null;
    final fetchedAt = DateTime.tryParse(row['fetched_at'] as String);
    if (fetchedAt == null) return null;
    try {
      final list = jsonDecode(row['days'] as String);
      if (list is! List) return null;
      return (
        fetchedAt: fetchedAt.toUtc(),
        days: [for (final d in list) ?DayWeather.fromJson(d)],
      );
    } on FormatException {
      return null;
    }
  }

  Future<void> _write(
    WeatherLocation location,
    DateTime fetchedAt,
    List<DayWeather> days,
  ) => _db.execute(
    'INSERT OR REPLACE INTO weather_cache (location_key, fetched_at, days) '
    'VALUES (?, ?, ?)',
    [
      location.cacheKey,
      fetchedAt.toUtc().toIso8601String(),
      jsonEncode([for (final d in days) d.toJson()]),
    ],
  );
}
