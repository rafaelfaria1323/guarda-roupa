import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../wear/domain/calendar_day.dart';
import '../domain/weather.dart';

/// O pedido falhou (rede, resposta inesperada ou tempo esgotado).
final class WeatherFetchFailed implements Exception {
  const WeatherFetchFailed(this.detail);
  final String detail;

  @override
  String toString() => 'WeatherFetchFailed: $detail';
}

/// Open-Meteo (docs/features/meteorologia.md): sem chave, uso pessoal não
/// comercial, com atribuição visível. Só envia coordenadas arredondadas (ou
/// o nome pesquisado).
final class OpenMeteoClient {
  OpenMeteoClient(this._http, {this.timeout = const Duration(seconds: 10)});

  final http.Client _http;
  final Duration timeout;

  static const forecastDays = 7;
  static const attribution = 'Open-Meteo.com';

  static Uri forecastUri(WeatherLocation location) {
    final l = location.rounded();
    return Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': l.latitude.toStringAsFixed(2),
      'longitude': l.longitude.toStringAsFixed(2),
      'hourly':
          'apparent_temperature,precipitation,precipitation_probability,'
          'wind_speed_10m',
      'wind_speed_unit': 'kmh',
      'timezone': l.timezone,
      'forecast_days': '$forecastDays',
    });
  }

  static Uri searchUri(String name) => Uri.https(
    'geocoding-api.open-meteo.com',
    '/v1/search',
    {'name': name, 'count': '8', 'language': 'pt', 'format': 'json'},
  );

  Future<List<DayWeather>> forecast(WeatherLocation location) async =>
      parseForecast(await _get(forecastUri(location)));

  /// Cidades com este nome (vazio se não houver).
  Future<List<WeatherLocation>> search(String name) async {
    final query = name.trim();
    if (query.length < 2) return const [];
    return parseSearch(await _get(searchUri(query)));
  }

  Future<Object?> _get(Uri uri) async {
    final http.Response response;
    try {
      response = await _http.get(uri).timeout(timeout);
    } on TimeoutException {
      throw const WeatherFetchFailed('timeout');
    } on http.ClientException catch (e) {
      throw WeatherFetchFailed(e.message);
    }
    if (response.statusCode != 200) {
      throw WeatherFetchFailed('HTTP ${response.statusCode}');
    }
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw const WeatherFetchFailed('invalid json');
    }
  }

  /// Agrega a previsão horária por dia, nas horas de [DayWeather.fromHour]
  /// a [DayWeather.toHour]. Um dia sem horas completas fica de fora.
  static List<DayWeather> parseForecast(Object? json) {
    if (json is! Map || json['hourly'] is! Map) {
      throw const WeatherFetchFailed('missing hourly');
    }
    final hourly = json['hourly'] as Map;
    List<Object?> col(String k) => switch (hourly[k]) {
      final List<Object?> l => l,
      _ => throw WeatherFetchFailed('missing $k'),
    };
    final times = col('time');
    final feels = col('apparent_temperature');
    final rain = col('precipitation');
    final wind = col('wind_speed_10m');
    final prob = hourly['precipitation_probability'] is List
        ? col('precipitation_probability')
        : null;
    final n = times.length;
    if (feels.length != n ||
        rain.length != n ||
        wind.length != n ||
        (prob != null && prob.length != n)) {
      throw const WeatherFetchFailed('columns differ');
    }

    final byDay = <CalendarDay, List<int>>{};
    for (var i = 0; i < n; i++) {
      final t = times[i];
      if (t is! String || t.length < 13) continue;
      final day = CalendarDay.tryParse(t.substring(0, 10));
      final hour = int.tryParse(t.substring(11, 13));
      if (day == null || hour == null) continue;
      if (hour < DayWeather.fromHour || hour > DayWeather.toHour) continue;
      (byDay[day] ??= []).add(i);
    }

    const hours = DayWeather.toHour - DayWeather.fromHour + 1;
    final days = <DayWeather>[];
    for (final MapEntry(key: day, value: idx) in byDay.entries) {
      double? at(List<Object?> c, int i) => switch (c[i]) {
        final num v => v.toDouble(),
        _ => null,
      };
      final f = [for (final i in idx) at(feels, i)];
      final r = [for (final i in idx) at(rain, i)];
      final w = [for (final i in idx) at(wind, i)];
      if (idx.length != hours ||
          f.contains(null) ||
          r.contains(null) ||
          w.contains(null)) {
        continue;
      }
      final fs = f.cast<double>();
      final ps = prob == null
          ? const <double>[]
          : [for (final i in idx) ?at(prob, i)];
      days.add(
        DayWeather(
          day: day,
          feelsLikeC: fs.reduce((a, b) => a + b) / fs.length,
          feelsLikeMinC: fs.reduce((a, b) => a < b ? a : b),
          feelsLikeMaxC: fs.reduce((a, b) => a > b ? a : b),
          precipitationMm: r.cast<double>().reduce((a, b) => a + b),
          windMaxKmh: w.cast<double>().reduce((a, b) => a > b ? a : b),
          precipitationProbability: ps.isEmpty
              ? null
              : ps.reduce((a, b) => a > b ? a : b).round(),
        ),
      );
    }
    days.sort((a, b) => a.day.compareTo(b.day));
    return days;
  }

  static List<WeatherLocation> parseSearch(Object? json) {
    if (json is! Map) throw const WeatherFetchFailed('invalid search');
    final results = json['results'];
    if (results is! List) return const [];
    return [
      for (final r in results)
        if (r is Map)
          if (WeatherLocation.fromJson({
                'name': r['name'],
                'region': r['admin1'] ?? r['country'],
                'latitude': r['latitude'],
                'longitude': r['longitude'],
                'timezone': r['timezone'],
              })
              case final l?)
            l.rounded(),
    ];
  }
}
