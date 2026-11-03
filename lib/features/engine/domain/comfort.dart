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

/// Limites de conforto aprovados (proposta de 2026-11-03, editáveis
/// depois): sensação ≥ 22 °C quente, 14–22 °C ameno, < 14 °C frio; chuva ou
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
