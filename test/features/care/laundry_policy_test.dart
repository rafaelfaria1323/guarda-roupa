import 'package:flutter_test/flutter_test.dart';
import 'package:guarda_roupa/features/care/domain/care_policies.dart';
import 'package:guarda_roupa/features/care/domain/cleaning_event.dart';
import 'package:guarda_roupa/features/care/domain/laundry_policy.dart';
import 'package:guarda_roupa/features/wardrobe/domain/availability.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment_category.dart';
import 'package:guarda_roupa/features/wear/domain/calendar_day.dart';
import 'package:guarda_roupa/features/wear/domain/wear_event.dart';

Garment garment(String id, GarmentCategory c) => Garment(
  id: GarmentId(id),
  category: c,
  availability: Availability.available,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

CalendarDay day(int d) => CalendarDay(2026, 11, d);

WearEvent wear(int d, List<String> ids, {int hour = 12}) => WearEvent(
  id: 'w$d-$hour',
  wornOn: day(d),
  garmentIds: [for (final id in ids) GarmentId(id)],
  createdAt: DateTime.utc(2026, 11, d, hour),
);

extension WearDay on WearEvent {
  WearEvent copyWithDay(CalendarDay d) => WearEvent(
    id: id,
    wornOn: d,
    garmentIds: garmentIds,
    createdAt: createdAt,
  );
}

CleaningEvent cleaning(int d, String id, {int hour = 12}) => CleaningEvent(
  id: 'c$d-$hour',
  garmentId: GarmentId(id),
  cleanedOn: day(d),
  createdAt: DateTime.utc(2026, 11, d, hour),
);

void main() {
  test('predefinidos aprovados em P-07', () {
    int d(GarmentCategory c) => LaundryPolicy.defaultFor(c);
    expect(d(GarmentCategory.tShirt), 1);
    expect(d(GarmentCategory.top), 1);
    expect(d(GarmentCategory.shirt), 2);
    expect(d(GarmentCategory.polo), 2);
    for (final c in [
      GarmentCategory.sweater,
      GarmentCategory.trousers,
      GarmentCategory.jeans,
      GarmentCategory.skirt,
      GarmentCategory.dress,
    ]) {
      expect(d(c), 4, reason: c.id);
    }
    for (final c in [
      GarmentCategory.coat,
      GarmentCategory.jacket,
      GarmentCategory.sneakers,
      GarmentCategory.boots,
    ]) {
      expect(d(c), 0, reason: c.id);
    }
  });

  test('peça > categoria > predefinido', () {
    final g = garment('a', GarmentCategory.jeans);
    expect(LaundryPolicy.thresholdFor(g, const CarePolicies()), 4);
    expect(
      LaundryPolicy.thresholdFor(
        g,
        const CarePolicies(laundryByCategory: {GarmentCategory.jeans: 6}),
      ),
      6,
    );
    expect(
      LaundryPolicy.thresholdFor(
        g,
        CarePolicies(
          laundryByCategory: const {GarmentCategory.jeans: 6},
          laundryByGarment: {g.id: 0},
        ),
      ),
      0,
    );
  });

  Map<GarmentId, LaundryState> run(
    List<Garment> garments,
    List<WearEvent> wears, [
    List<CleaningEvent> cleanings = const [],
    CarePolicies policies = const CarePolicies(),
  ]) => LaundryPolicy.evaluate(
    garments: garments,
    wears: wears,
    cleanings: cleanings,
    policies: policies,
  );

  test('conta utilizações desde a última limpeza', () {
    final jeans = garment('j', GarmentCategory.jeans);
    final s = run(
      [jeans],
      [
        wear(1, ['j']),
        wear(2, ['j']),
        wear(4, ['j']),
        wear(5, ['j']),
      ],
      [cleaning(1, 'j'), cleaning(3, 'j')],
    )[jeans.id]!;
    expect(s.usesSinceCleaning, 2);
    expect(s.lastCleanedOn, day(3));
    expect(s.washRecommended, isFalse);
  });

  test('no mesmo dia conta a ordem de registo', () {
    final t = garment('t', GarmentCategory.tShirt);
    final before = run(
      [t],
      [
        wear(3, ['t'], hour: 9),
      ],
      [cleaning(3, 't')],
    );
    expect(before[t.id]!.usesSinceCleaning, 0);
    final after = run(
      [t],
      [
        wear(3, ['t'], hour: 20),
      ],
      [cleaning(3, 't')],
    );
    expect(after[t.id]!.usesSinceCleaning, 1);
    expect(after[t.id]!.washRecommended, isTrue, reason: 'após cada uso');
  });

  test('sem limpeza registada conta tudo; não presume lavada', () {
    final shirt = garment('s', GarmentCategory.shirt);
    final s = run(
      [shirt],
      [
        wear(1, ['s']),
        wear(2, ['s']),
      ],
    )[shirt.id]!;
    expect(s.usesSinceCleaning, 2);
    expect(s.lastCleanedOn, isNull);
    expect(s.washRecommended, isTrue);
  });

  test('sem aviso (0) nunca recomenda; peças sem uso ficam a zero', () {
    final coat = garment('c', GarmentCategory.coat);
    final other = garment('o', GarmentCategory.tShirt);
    final s = run(
      [coat, other],
      [
        for (var d = 1; d <= 9; d++) wear(d, ['c']),
      ],
    );
    expect(s[coat.id]!.usesSinceCleaning, 9);
    expect(s[coat.id]!.washRecommended, isFalse);
    expect(s[other.id]!.usesSinceCleaning, 0);
  });

  group('dirtyAfterWear', () {
    List<String> dirty(
      WearEvent event, {
      List<Garment>? garments,
      List<WearEvent> wears = const [],
      List<CleaningEvent> cleanings = const [],
    }) => [
      for (final id in LaundryPolicy.dirtyAfterWear(
        event,
        garments:
            garments ??
            [
              garment('t', GarmentCategory.tShirt),
              garment('j', GarmentCategory.jeans),
              garment('s', GarmentCategory.sneakers),
            ],
        wears: wears,
        cleanings: cleanings,
        policies: const CarePolicies(),
      ))
        id.value,
    ];

    test('a t-shirt suja-se à primeira; ganga à quarta; calçado nunca', () {
      final today = wear(10, ['t', 'j', 's']);
      expect(dirty(today), ['t']);
      final before = [
        for (var d = 1; d <= 3; d++) wear(d, ['j']),
      ];
      expect(dirty(today, wears: before), ['t', 'j']);
    });

    test('o evento já na lista conta uma vez', () {
      final today = wear(10, ['j']);
      final before = [
        for (var d = 1; d <= 2; d++) wear(d, ['j']),
      ];
      expect(dirty(today, wears: [...before, today]), isEmpty);
    });

    test('uma limpeza depois reinicia a contagem', () {
      final today = wear(10, ['j']);
      final before = [
        for (var d = 1; d <= 3; d++) wear(d, ['j']),
      ];
      expect(
        dirty(today, wears: before, cleanings: [cleaning(5, 'j')]),
        isEmpty,
      );
    });

    test('peças já indisponíveis ou de fora ficam como estão', () {
      final washing = Garment(
        id: const GarmentId('t'),
        category: GarmentCategory.tShirt,
        availability: Availability.washing,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );
      expect(dirty(wear(10, ['t']), garments: [washing]), isEmpty);
      expect(dirty(wear(10, ['x'])), isEmpty);
    });
  });

  test('etiqueta que pede limpeza profissional', () {
    expect(LaundryPolicy.asksProfessional('Limpeza a seco'), isTrue);
    expect(LaundryPolicy.asksProfessional('NÃO LAVAR. Só a seco.'), isTrue);
    expect(LaundryPolicy.asksProfessional('Dry clean only'), isTrue);
    expect(LaundryPolicy.asksProfessional('Lavar à máquina a 30 °C'), isFalse);
    expect(LaundryPolicy.asksProfessional(null), isFalse);
  });
}
