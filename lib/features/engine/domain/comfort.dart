import '../../wardrobe/domain/garment_attributes.dart';

/// Condições do dia que o motor usa. Quem as obtém (previsão ou contexto
/// manual) decide o que é "chuva"; aqui só se aplica a política.
final class WeatherConditions {
  const WeatherConditions({
    required this.feelsLikeC,
    this.rain = false,
    this.windKmh = 0,
  });

  /// Sensação térmica (ou temperatura, quando não há sensação).
  final double feelsLikeC;
  final bool rain;
  final double windKmh;
}

enum ComfortBand {
  /// Peças leves; sem camadas.
  hot,

  /// Peças médias (ou leves); camada opcional.
  mild,

  /// Peças quentes, ou uma peça leve/média mais um casaco.
  cold,
}

/// Limites de conforto aprovados (proposta de 2026-11-03, editáveis nas
/// Definições): sensação ≥ 22 °C quente, 14–22 °C ameno, < 14 °C frio; chuva ou
/// vento ≥ 30 km/h preferem peças marcadas para chuva/vento.
final class ComfortThresholds {
  const ComfortThresholds({
    this.hotFromC = 22,
    this.coldBelowC = 14,
    this.windyFromKmh = 30,
  });

  final double hotFromC;
  final double coldBelowC;
  final double windyFromKmh;

  /// Limites que o ecrã de edição deixa escolher.
  static const hotRange = (min: 15.0, max: 35.0);
  static const coldRange = (min: 0.0, max: 25.0);
  static const windRange = (min: 10.0, max: 80.0);

  /// Frio abaixo do calor, todos dentro dos limites.
  bool get isValid =>
      coldBelowC < hotFromC &&
      _within(hotFromC, hotRange) &&
      _within(coldBelowC, coldRange) &&
      _within(windyFromKmh, windRange);

  static bool _within(double v, ({double min, double max}) r) =>
      v >= r.min && v <= r.max;

  Map<String, Object?> toJson() => {
    'hot_from_c': hotFromC,
    'cold_below_c': coldBelowC,
    'windy_from_kmh': windyFromKmh,
  };

  /// `null` se faltar um valor ou a combinação não for válida.
  static ComfortThresholds? fromJson(Object? json) {
    if (json is! Map) return null;
    final hot = json['hot_from_c'];
    final cold = json['cold_below_c'];
    final wind = json['windy_from_kmh'];
    if (hot is! num || cold is! num || wind is! num) return null;
    final t = ComfortThresholds(
      hotFromC: hot.toDouble(),
      coldBelowC: cold.toDouble(),
      windyFromKmh: wind.toDouble(),
    );
    return t.isValid ? t : null;
  }

  @override
  bool operator ==(Object other) =>
      other is ComfortThresholds &&
      other.hotFromC == hotFromC &&
      other.coldBelowC == coldBelowC &&
      other.windyFromKmh == windyFromKmh;

  @override
  int get hashCode => Object.hash(hotFromC, coldBelowC, windyFromKmh);

  ComfortBand bandFor(WeatherConditions w) {
    if (w.feelsLikeC >= hotFromC) return ComfortBand.hot;
    if (w.feelsLikeC < coldBelowC) return ComfortBand.cold;
    return ComfortBand.mild;
  }

  bool isWindy(WeatherConditions w) => w.windKmh >= windyFromKmh;
}

/// Adequação de uma peça principal (top, parte de baixo, peça única).
enum ComfortFit {
  fits,

  /// Só serve com um casaco por cima (frio com peça leve ou média).
  fitsWithOuterLayer,

  /// Aquecimento desconhecido: não se exclui, diz-se.
  unknown,
  mismatch,
}

abstract final class ComfortRules {
  static ComfortFit fitOf(Warmth? warmth, ComfortBand band) {
    if (warmth == null) return ComfortFit.unknown;
    return switch ((band, warmth)) {
      (ComfortBand.hot, Warmth.light) => ComfortFit.fits,
      (ComfortBand.hot, _) => ComfortFit.mismatch,
      (ComfortBand.mild, Warmth.warm) => ComfortFit.mismatch,
      (ComfortBand.mild, _) => ComfortFit.fits,
      (ComfortBand.cold, Warmth.warm) => ComfortFit.fits,
      (ComfortBand.cold, _) => ComfortFit.fitsWithOuterLayer,
    };
  }
}
