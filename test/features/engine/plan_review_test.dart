import 'package:flutter_test/flutter_test.dart';
import 'package:guarda_roupa/features/engine/domain/comfort.dart';
import 'package:guarda_roupa/features/engine/domain/plan_review.dart';
import 'package:guarda_roupa/features/engine/domain/suggestion.dart';
import 'package:guarda_roupa/features/outfits/domain/outfit.dart';
import 'package:guarda_roupa/features/wardrobe/domain/availability.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment_attributes.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment_category.dart';
import 'package:guarda_roupa/features/wear/domain/wear_event.dart';

import 'daily_engine_test.dart' show cold, day, g, hot, wore;

OutfitItem it(String id, OutfitRole role) => OutfitItem(GarmentId(id), role);

final outfit = [
  it('t1', OutfitRole.mainTop),
  it('b1', OutfitRole.bottom),
  it('s1', OutfitRole.footwear),
];

List<DayReview> review(
  List<Garment> garments,
  List<ReviewDay> days, {
  List<WearEvent> wears = const [],
}) =>
    PlanReview.review(WardrobeSnapshot(garments: garments, wears: wears), days);

List<String> ids(List<OutfitItem> items) => [
  for (final i in items) i.garmentId.value,
];

void main() {
  test('nada mudou: nenhum dia afetado', () {
    final result = review(
      [
        g('t1', GarmentCategory.tShirt),
        g('b1', GarmentCategory.jeans),
        g('s1', GarmentCategory.sneakers),
      ],
      [ReviewDay(day: day(10), items: outfit)],
    );
    expect(result.single.affected, isFalse);
    expect(result.single.proposal, isNull);
  });

  test('peça a lavar: só essa muda, as outras ficam', () {
    final result = review(
      [
        g('t1', GarmentCategory.tShirt, availability: Availability.washing),
        g('t2', GarmentCategory.tShirt),
        g('b1', GarmentCategory.jeans),
        g('b2', GarmentCategory.jeans),
        g('s1', GarmentCategory.sneakers),
      ],
      [ReviewDay(day: day(10), items: outfit)],
    );
    final d = result.single;
    expect(d.issues.single, isA<GarmentUnavailable>());
    expect(
      (d.issues.single as GarmentUnavailable).availability,
      Availability.washing,
    );
    expect(ids(d.proposal!.items), ['t2', 'b1', 's1']);
    expect(ids(d.proposal!.added), ['t2']);
    expect(d.proposal!.dropped, isEmpty);
  });

  test('arquivada e sem substituta: sai e o papel fica dito', () {
    final result = review(
      [
        g('t1', GarmentCategory.tShirt),
        g('b1', GarmentCategory.jeans),
        g('s1', GarmentCategory.sneakers, archived: true),
      ],
      [ReviewDay(day: day(10), items: outfit)],
    );
    final d = result.single;
    expect(d.issues.single, isA<GarmentGone>());
    expect(ids(d.proposal!.items), ['t1', 'b1']);
    expect(d.proposal!.dropped, [OutfitRole.footwear]);
  });

  test('previsão mudou para calor: a camisola quente é trocada', () {
    final result = review(
      [
        g('t1', GarmentCategory.sweater, warmth: Warmth.warm),
        g('t2', GarmentCategory.tShirt, warmth: Warmth.light),
        g('b1', GarmentCategory.jeans, warmth: Warmth.medium),
        g('s1', GarmentCategory.sneakers),
      ],
      [ReviewDay(day: day(10), items: outfit, weather: hot)],
    );
    final d = result.single;
    expect(d.issues.single, isA<ComfortUnsuited>());
    expect((d.issues.single as ComfortUnsuited).band, ComfortBand.hot);
    expect(ids(d.proposal!.items), ['t2', 'b1', 's1']);
  });

  test('previsão mudou para frio: junta um casaco, a t-shirt fica', () {
    final garments = [
      g('t1', GarmentCategory.tShirt, warmth: Warmth.light),
      g('b1', GarmentCategory.jeans, warmth: Warmth.medium),
      g('s1', GarmentCategory.sneakers),
    ];
    final d = review(
      [...garments, g('c1', GarmentCategory.coat)],
      [ReviewDay(day: day(10), items: outfit, weather: cold)],
    ).single;
    expect(d.issues.single, isA<OuterLayerNeeded>());
    expect(ids(d.proposal!.items), ['t1', 'c1', 'b1', 's1']);

    final none = review(garments, [
      ReviewDay(day: day(10), items: outfit, weather: cold),
    ]).single;
    expect(none.proposal!.dropped, [OutfitRole.outerLayer]);
    expect(ids(none.proposal!.items), ['t1', 'b1', 's1']);
  });

  test('chuva prevista e calçado que não é para chuva', () {
    final result = review(
      [
        g('t1', GarmentCategory.tShirt),
        g('b1', GarmentCategory.jeans),
        g('s1', GarmentCategory.sneakers, rainOk: false),
        g('s2', GarmentCategory.boots, rainOk: true),
      ],
      [
        ReviewDay(
          day: day(10),
          items: outfit,
          weather: const WeatherConditions(feelsLikeC: 18, rain: true),
        ),
      ],
    );
    final d = result.single;
    expect(d.issues.single, isA<WeatherUnsuited>());
    expect(ids(d.proposal!.added), ['s2']);
  });

  test('uso real depois de planear: lavagem recomendada, sem reescrever', () {
    // t1 vestida hoje (dia 9); estava planeada para quarta.
    final result = review(
      [
        g('t1', GarmentCategory.tShirt),
        g('t2', GarmentCategory.tShirt),
        g('b1', GarmentCategory.jeans),
        g('s1', GarmentCategory.sneakers),
      ],
      [ReviewDay(day: day(11), items: outfit)],
      wears: [
        wore(9, ['t1']),
      ],
    );
    final d = result.single;
    expect(d.issues.single, isA<WashDue>());
    expect(ids(d.proposal!.added), ['t2']);
  });

  test('dias confirmados não se reveem; a troca vê as reservas anteriores', () {
    final garments = [
      g('t1', GarmentCategory.tShirt, availability: Availability.washing),
      g('t2', GarmentCategory.tShirt),
      g('t3', GarmentCategory.tShirt),
      g('b1', GarmentCategory.jeans),
      g('s1', GarmentCategory.sneakers),
    ];
    final result = review(garments, [
      ReviewDay(day: day(9), items: outfit, reviewable: false),
      ReviewDay(
        day: day(10),
        items: [
          it('t2', OutfitRole.mainTop),
          it('b1', OutfitRole.bottom),
          it('s1', OutfitRole.footwear),
        ],
      ),
      ReviewDay(day: day(11), items: outfit),
    ]);
    expect(result[0].affected, isFalse);
    expect(result[1].affected, isFalse);
    expect(ids(result[2].proposal!.added), [
      't3',
    ], reason: 't2 fica reservada para terça');
  });
}
