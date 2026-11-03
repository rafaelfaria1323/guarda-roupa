import 'package:flutter_test/flutter_test.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment_category.dart';

void main() {
  test('IDs estáveis fazem ida e volta e são únicos', () {
    final ids = GarmentCategory.values.map((c) => c.id).toList();
    expect(ids.toSet().length, ids.length);
    for (final c in GarmentCategory.values) {
      expect(GarmentCategory.fromId(c.id), c);
    }
    expect(GarmentCategory.fromId('desconhecida'), isNull);
  });

  test('t-shirt pertence ao grupo top, não a uma camada', () {
    expect(GarmentCategory.tShirt.id, 't_shirt');
    expect(GarmentCategory.tShirt.group, CategoryGroup.top);
  });
}
