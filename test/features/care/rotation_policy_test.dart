import 'package:flutter_test/flutter_test.dart';
import 'package:guarda_roupa/features/care/domain/care_policies.dart';
import 'package:guarda_roupa/features/care/domain/rotation_policy.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment_category.dart';
import 'package:guarda_roupa/features/wear/domain/calendar_day.dart';
import 'package:guarda_roupa/features/wear/domain/wear_event.dart';

import 'laundry_policy_test.dart' show WearDay, day, garment, wear;

void main() {
  test('predefinidos aprovados em P-06', () {
    int d(GarmentCategory c) => RotationPolicy.defaultFor(c);
    expect(d(GarmentCategory.tShirt), 3);
    expect(d(GarmentCategory.sweater), 3);
    expect(d(GarmentCategory.trousers), 2);
    expect(d(GarmentCategory.skirt), 2);
    expect(d(GarmentCategory.shorts), 2);
    expect(d(GarmentCategory.coat), 0);
    expect(d(GarmentCategory.sneakers), 0);
    expect(d(GarmentCategory.accessory), 0);
  });

  Map<GarmentId, RotationState> run(
    List<Garment> garments,
    List<WearEvent> wears, {
    CarePolicies policies = const CarePolicies(),
    int today = 3,
  }) => RotationPolicy.evaluate(
    garments: garments,
    wears: wears,
    policies: policies,
    today: day(today),
  );

  test('com 3, usada no dia 1 volta a ser elegível no dia 4', () {
    final t = garment('t', GarmentCategory.tShirt);
    final wears = [
      wear(1, ['t']),
    ];
    expect(run([t], wears, today: 2)[t.id]!.eligibleFrom, day(4));
    expect(run([t], wears, today: 3)[t.id]!.isEligible, isFalse);
    expect(run([t], wears, today: 4)[t.id]!.isEligible, isTrue);
  });

  test('dias de calendário atravessam a mudança de hora', () {
    final t = garment('t', GarmentCategory.tShirt);
    final s = RotationPolicy.evaluate(
      garments: [t],
      wears: [
        wear(1, ['t']).copyWithDay(CalendarDay(2026, 10, 24)),
      ],
      policies: const CarePolicies(),
      today: CalendarDay(2026, 10, 25),
    );
    expect(s[t.id]!.eligibleFrom, CalendarDay(2026, 10, 27));
  });

  test('peça > categoria > predefinido; 0 = sem intervalo', () {
    final j = garment('j', GarmentCategory.jeans);
    final wears = [
      wear(3, ['j']),
    ];
    expect(run([j], wears)[j.id]!.eligibleFrom, day(5));
    expect(
      run(
        [j],
        wears,
        policies: const CarePolicies(
          rotationByCategory: {GarmentCategory.jeans: 4},
        ),
      )[j.id]!.eligibleFrom,
      day(7),
    );
    expect(
      run(
        [j],
        wears,
        policies: CarePolicies(
          rotationByCategory: const {GarmentCategory.jeans: 4},
          rotationByGarment: {j.id: 0},
        ),
      )[j.id]!.isEligible,
      isTrue,
    );
  });

  test('ordem: elegíveis, menos usadas, usadas há mais tempo', () {
    final a = garment('a', GarmentCategory.tShirt);
    final b = garment('b', GarmentCategory.tShirt);
    final c = garment('c', GarmentCategory.tShirt);
    final fresh = garment('d', GarmentCategory.tShirt);
    final states = run(
      [a, b, c, fresh],
      [
        wear(1, ['a']),
        wear(2, ['a']),
        wear(1, ['b']),
        wear(9, ['c']), // ainda fora da rotação no dia 10
      ],
      today: 10,
    );
    final ranked = RotationPolicy.rank([a, b, c, fresh], states);
    expect(ranked.map((r) => r.garment.id.value), ['d', 'b', 'a', 'c']);
    expect(ranked.any((r) => r.warning), isFalse);
  });

  test('sem alternativa elegível: sugere na mesma, com aviso', () {
    final a = garment('a', GarmentCategory.tShirt);
    final b = garment('b', GarmentCategory.tShirt);
    final states = run(
      [a, b],
      [
        wear(2, ['a']),
        wear(3, ['b']),
      ],
    );
    final ranked = RotationPolicy.rank([a, b], states);
    expect(ranked.map((r) => r.garment.id.value), ['a', 'b']);
    expect(ranked.every((r) => r.warning), isTrue);
  });

  test('reservas futuras não contam como utilização', () {
    final t = garment('t', GarmentCategory.tShirt);
    final s = run(
      [t],
      [
        wear(5, ['t']),
      ],
      today: 3,
    )[t.id]!;
    expect(s.lastWornOn, isNull);
    expect(s.isEligible, isTrue);
  });
}
