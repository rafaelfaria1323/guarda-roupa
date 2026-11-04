import 'package:flutter_test/flutter_test.dart';
import 'package:guarda_roupa/features/engine/domain/comfort.dart';

void main() {
  test('JSON ida e volta', () {
    const t = ComfortThresholds(hotFromC: 25, coldBelowC: 12, windyFromKmh: 40);
    expect(ComfortThresholds.fromJson(t.toJson()), t);
  });

  test('rejeita combinações inválidas ou incompletas', () {
    expect(ComfortThresholds.fromJson(null), isNull);
    expect(ComfortThresholds.fromJson({'hot_from_c': 22}), isNull);
    expect(
      ComfortThresholds.fromJson({
        'hot_from_c': 14,
        'cold_below_c': 14,
        'windy_from_kmh': 30,
      }),
      isNull,
      reason: 'frio tem de ficar abaixo do calor',
    );
    expect(
      ComfortThresholds.fromJson({
        'hot_from_c': 22,
        'cold_below_c': 14,
        'windy_from_kmh': 200,
      }),
      isNull,
    );
  });

  test('os valores de origem são válidos', () {
    expect(const ComfortThresholds().isValid, isTrue);
  });

  test('limites editados mudam a banda', () {
    const w = WeatherConditions(feelsLikeC: 20);
    expect(const ComfortThresholds().bandFor(w), ComfortBand.mild);
    expect(const ComfortThresholds(hotFromC: 19).bandFor(w), ComfortBand.hot);
    expect(
      const ComfortThresholds(hotFromC: 25, coldBelowC: 21).bandFor(w),
      ComfortBand.cold,
    );
  });
}
