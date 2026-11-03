import 'package:flutter_test/flutter_test.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment_color.dart';

void main() {
  test('aceita RGB e proporção válidos', () {
    final c = GarmentColor.create(rgb: 0x61745B, proportion: 0.5);
    expect(c, isNotNull);
    expect(c!.confirmed, isFalse);
  });

  test('rejeita RGB fora de 0x000000..0xFFFFFF', () {
    expect(GarmentColor.create(rgb: -1, proportion: 0.5), isNull);
    expect(GarmentColor.create(rgb: 0x1000000, proportion: 0.5), isNull);
  });

  test('rejeita proporção nula, negativa, acima de 1 ou NaN', () {
    for (final p in [0.0, -0.1, 1.01, double.nan]) {
      expect(GarmentColor.create(rgb: 0, proportion: p), isNull, reason: '$p');
    }
    expect(GarmentColor.create(rgb: 0, proportion: 1), isNotNull);
  });
}
