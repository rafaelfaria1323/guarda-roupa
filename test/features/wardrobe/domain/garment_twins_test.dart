import 'package:flutter_test/flutter_test.dart';
import 'package:guarda_roupa/features/wardrobe/domain/availability.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment_category.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment_twins.dart';
import 'package:guarda_roupa/features/wear/domain/calendar_day.dart';

void main() {
  var n = 0;
  Garment g({
    String? name,
    String? brand,
    GarmentCategory category = GarmentCategory.tShirt,
    Availability availability = Availability.available,
    DateTime? archivedAt,
  }) {
    n++;
    final created = DateTime.utc(2026, 1, n);
    return Garment(
      id: GarmentId('g$n'),
      category: category,
      availability: availability,
      createdAt: created,
      updatedAt: created,
      name: name,
      brand: brand,
      archivedAt: archivedAt,
    );
  }

  group('iguais', () {
    test('mesma categoria, nome e marca, sem contar maiúsculas e espaços', () {
      final a = g(name: 'Branca', brand: 'Zara');
      final b = g(name: ' branca ', brand: 'ZARA');
      final other = g(name: 'Branca', brand: 'Mango');
      final shirt = g(name: 'Branca', category: GarmentCategory.shirt);
      final groups = GarmentTwins.group([a, other, b, shirt]);
      expect(groups.map((u) => u.map((x) => x.id.value).toList()), [
        ['g1', 'g2'],
        ['g3'],
        ['g4'],
      ]);
    });

    test('sem nome nem cores cada peça fica sozinha', () {
      expect(GarmentTwins.key(g()), isNull);
      expect(GarmentTwins.group([g(), g()]), hasLength(2));
    });

    test('arquivada não se junta à que está no armário', () {
      final a = g(name: 'Branca');
      final b = g(name: 'Branca', archivedAt: DateTime.utc(2026, 2));
      expect(GarmentTwins.group([a, b]), hasLength(2));
    });
  });

  group('escolher a unidade', () {
    test(
      'disponível, nunca usada, depois a que está há mais tempo sem uso',
      () {
        final dirty = g(name: 'B', availability: Availability.needsCleaning);
        final recent = g(name: 'B');
        final old = g(name: 'B');
        final lastWorn = {
          dirty.id: CalendarDay(2026, 1, 1),
          recent.id: CalendarDay(2026, 11, 5),
          old.id: CalendarDay(2026, 10, 1),
        };
        expect(
          GarmentTwins.pick([dirty, recent, old], lastWorn: lastWorn),
          same(old),
        );
        final fresh = g(name: 'B');
        expect(
          GarmentTwins.pick([dirty, recent, old, fresh], lastWorn: lastWorn),
          same(fresh),
        );
      },
    );

    test('empate: a mais antiga', () {
      final a = g(name: 'B');
      final b = g(name: 'B');
      expect(GarmentTwins.pick([b, a], lastWorn: const {}), same(a));
    });
  });
}
