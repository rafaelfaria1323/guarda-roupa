import '../../engine/domain/comfort.dart';
import '../../wear/domain/calendar_day.dart';

/// Local da previsão (P-18): escolhido à mão, coordenadas aproximadas da
/// cidade (duas casas decimais, ~1 km). Sem GPS.
final class WeatherLocation {
  const WeatherLocation({
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.timezone,
    this.region,
  });

  /// Predefinido aprovado em P-18.
  static const torresVedras = WeatherLocation(
    name: 'Torres Vedras',
    region: 'Lisboa',
    latitude: 39.09,
    longitude: -9.26,
    timezone: 'Europe/Lisbon',
  );

  final String name;

  /// Distrito/região, para distinguir cidades com o mesmo nome.
  final String? region;
  final double latitude;
  final double longitude;
  final String timezone;

  /// Coordenadas arredondadas: só isto sai do dispositivo.
  WeatherLocation rounded() => WeatherLocation(
    name: name,
    region: region,
    latitude: _round2(latitude),
    longitude: _round2(longitude),
    timezone: timezone,
  );

  /// Identifica a cache: mudar de local nunca reaproveita outra previsão.
  String get cacheKey =>
      '${_round2(latitude).toStringAsFixed(2)},'
      '${_round2(longitude).toStringAsFixed(2)}';

  Map<String, Object?> toJson() => {
    'name': name,
    'region': region,
    'latitude': latitude,
    'longitude': longitude,
    'timezone': timezone,
  };

  static WeatherLocation? fromJson(Object? json) {
    if (json is! Map) return null;
    final name = json['name'];
    final lat = json['latitude'];
    final lon = json['longitude'];
    final tz = json['timezone'];
    final region = json['region'];
    if (name is! String || name.isEmpty || tz is! String || tz.isEmpty) {
      return null;
    }
    if (lat is! num || lon is! num) return null;
    if (lat.abs() > 90 || lon.abs() > 180) return null;
    return WeatherLocation(
      name: name,
      region: region is String ? region : null,
      latitude: lat.toDouble(),
      longitude: lon.toDouble(),
      timezone: tz,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is WeatherLocation &&
      other.cacheKey == cacheKey &&
      other.name == name &&
      other.timezone == timezone;

  @override
  int get hashCode => Object.hash(cacheKey, name, timezone);

  static double _round2(double v) => (v * 100).roundToDouble() / 100;
}

/// Resumo de um dia, calculado a partir da previsão horária entre as
/// [DayWeather.fromHour] e as [DayWeather.toHour] (hora local do sítio).
final class DayWeather {
  const DayWeather({
    required this.day,
    required this.feelsLikeC,
    required this.feelsLikeMinC,
    required this.feelsLikeMaxC,
    required this.precipitationMm,
    required this.windMaxKmh,
    this.precipitationProbability,
    this.uvIndexMax,
  });

  /// Horas que contam para vestir: o dia, não a madrugada.
  static const fromHour = 8;
  static const toHour = 20;

  final CalendarDay day;

  /// Média da sensação térmica nessas horas.
  final double feelsLikeC;
  final double feelsLikeMinC;
  final double feelsLikeMaxC;

  /// Soma nessas horas.
  final double precipitationMm;

  /// Máximo nessas horas (%); `null` se o fornecedor não o deu.
  final int? precipitationProbability;
  final double windMaxKmh;

  /// Índice UV máximo nessas horas; `null` se o fornecedor não o deu
  /// (ou numa cópia guardada antes de existir).
  final double? uvIndexMax;

  Map<String, Object?> toJson() => {
    'day': day.iso,
    'feels_like': feelsLikeC,
    'feels_like_min': feelsLikeMinC,
    'feels_like_max': feelsLikeMaxC,
    'precipitation': precipitationMm,
    'precipitation_probability': precipitationProbability,
    'wind_max': windMaxKmh,
    'uv_index_max': uvIndexMax,
  };

  static DayWeather? fromJson(Object? json) {
    if (json is! Map) return null;
    final day = CalendarDay.tryParse(json['day'] as String?);
    double? n(String k) => switch (json[k]) {
      final num v => v.toDouble(),
      _ => null,
    };
    final feels = n('feels_like');
    final min = n('feels_like_min');
    final max = n('feels_like_max');
    final rain = n('precipitation');
    final wind = n('wind_max');
    if (day == null ||
        feels == null ||
        min == null ||
        max == null ||
        rain == null ||
        wind == null) {
      return null;
    }
    return DayWeather(
      day: day,
      feelsLikeC: feels,
      feelsLikeMinC: min,
      feelsLikeMaxC: max,
      precipitationMm: rain,
      windMaxKmh: wind,
      precipitationProbability: switch (json['precipitation_probability']) {
        final num v => v.round(),
        _ => null,
      },
      uvIndexMax: n('uv_index_max'),
    );
  }
}

/// O que conta como "chuva" para preferir peças marcadas para chuva
/// (P-17). Valores técnicos iniciais, a rever com o utilizador.
abstract final class RainRule {
  static const minPrecipitationMm = 1.0;
  static const minProbability = 50;

  static bool isRainy(DayWeather d) =>
      d.precipitationMm >= minPrecipitationMm ||
      (d.precipitationProbability ?? 0) >= minProbability;
}

/// O que conta como "dia de sol" para sugerir óculos de sol (e chapéu,
/// se estiver calor): índice UV moderado ou mais e sem chuva.
abstract final class SunRule {
  static const minUvIndex = 3.0;

  static bool isSunny(DayWeather d) =>
      (d.uvIndexMax ?? 0) >= minUvIndex && !RainRule.isRainy(d);
}

extension DayWeatherConditions on DayWeather {
  WeatherConditions toConditions() => WeatherConditions(
    feelsLikeC: feelsLikeC,
    rain: RainRule.isRainy(this),
    windKmh: windMaxKmh,
    sunny: SunRule.isSunny(this),
  );
}

/// Frescura da previsão (docs/features/meteorologia.md: recente, antiga,
/// ausente).
enum ForecastFreshness {
  /// Obtida há menos de [WeatherReport.freshFor].
  fresh,

  /// Só havia uma cópia antiga (sem rede ou o pedido falhou).
  stale,
}

/// Porque não há previsão para o dia pedido.
enum ForecastGap {
  /// Nunca se conseguiu obter (sem rede ou o pedido falhou).
  unavailable,

  /// Fora do horizonte do fornecedor (ou já passou).
  outOfRange,
}

final class WeatherReport {
  const WeatherReport.forecast({
    required DayWeather this.weather,
    required DateTime this.fetchedAt,
    required ForecastFreshness this.freshness,
    required this.location,
  }) : gap = null;

  const WeatherReport.missing(ForecastGap this.gap, {required this.location})
    : weather = null,
      fetchedAt = null,
      freshness = null;

  /// Até aqui a previsão guardada é "recente".
  static const freshFor = Duration(hours: 6);

  final WeatherLocation location;
  final DayWeather? weather;
  final DateTime? fetchedAt;
  final ForecastFreshness? freshness;
  final ForecastGap? gap;
}
