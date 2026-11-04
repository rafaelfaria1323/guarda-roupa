import 'package:flutter_test/flutter_test.dart';
import 'package:guarda_roupa/features/engine/domain/suggestion.dart';
import 'package:guarda_roupa/features/engine/domain/weekly_planner.dart';
import 'package:guarda_roupa/features/outfits/domain/outfit.dart';
import 'package:guarda_roupa/features/wardrobe/domain/availability.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment_attributes.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment_category.dart';
import 'package:guarda_roupa/features/wear/domain/wear_event.dart';

import 'daily_engine_test.dart' show day, g, wore;

WeekPlanResult plan(
  List<Garment> garments,
  List<WeekDayRequest> days, {
  List<WearEvent> wears = const [],
  int beamWidth = 8,
}) => WeeklyPlanner.plan(
  WardrobeSnapshot(garments: garments, wears: wears),
  WeekRequest(days: days, beamWidth: beamWidth),
);

List<WeekDayRequest> week({int from = 9, int days = 7}) => [
  for (var d = from; d < from + days; d++) WeekDayRequest(day: day(d)),
];

String? top(DayPlan d) => [
  for (final i in d.items)
    if (i.role == OutfitRole.mainTop) i.garmentId.value,
].firstOrNull;

void main() {
  test('7 dias com roupa suficiente: sem avisos de rotatividade', () {
    final result = plan([
      for (final t in ['t1', 't2', 't3']) g(t, GarmentCategory.tShirt),
      for (final b in ['b1', 'b2', 'b3']) g(b, GarmentCategory.jeans),
      g('s1', GarmentCategory.sneakers),
    ], week());
    expect(result.days, hasLength(7));
    expect(result.days.map((d) => d.status).toSet(), {DayPlanStatus.planned});
    for (final d in result.days) {
      expect(
        d.candidate!.items
            .expand((i) => i.warnings)
            .whereType<RotationExceeded>(),
        isEmpty,
        reason: '${d.day}',
      );
    }
    // Os mesmos ténis todos os dias é normal (sem rotatividade).
    expect(
      result.days.every((d) => d.items.any((i) => i.garmentId.value == 's1')),
      isTrue,
    );
    // Três tops, três dias de intervalo: rodam.
    expect(result.days.take(3).map(top).toSet(), hasLength(3));
    expect(result.explored, greaterThan(7));
  });

  test('não gasta cedo a única peça que outro dia precisa', () {
    // Segunda sem ocasião; terça no trabalho, e só "tw" serve. "tw" nunca
    // foi usada e "tc" foi usada há uma semana: escolhas dia a dia davam
    // "tw" na segunda e uma t-shirt em rotação na terça.
    final garments = [
      g('tw', GarmentCategory.tShirt, occasions: {Occasion.workCasual}),
      g('tc', GarmentCategory.tShirt, occasions: {Occasion.casual}),
      g(
        'b1',
        GarmentCategory.jeans,
        occasions: {Occasion.casual, Occasion.workCasual},
      ),
      g(
        'b2',
        GarmentCategory.jeans,
        occasions: {Occasion.casual, Occasion.workCasual},
      ),
      g(
        's1',
        GarmentCategory.sneakers,
        occasions: {Occasion.casual, Occasion.workCasual},
      ),
    ];
    final days = [
      WeekDayRequest(day: day(9)),
      WeekDayRequest(day: day(10), occasion: Occasion.workCasual),
    ];
    final wears = [
      wore(2, ['tc']),
    ];
    final greedy = plan(garments, days, wears: wears, beamWidth: 1);
    expect(greedy.days.map(top), ['tw', 'tw']);

    final beam = plan(garments, days, wears: wears);
    expect(beam.days.map(top), ['tc', 'tw']);
    expect(beam.days.expand((d) => d.repeats), isEmpty);
  });

  test('roupa escassa: repete e diz que repete, sem esconder a regra', () {
    final result = plan([
      g('t1', GarmentCategory.tShirt),
      g('b1', GarmentCategory.jeans),
      g('s1', GarmentCategory.sneakers),
    ], week(days: 3));
    expect(result.days.map(top), ['t1', 't1', 't1']);
    expect(result.days.first.repeats, isEmpty);
    expect(result.days[1].repeats, {
      const GarmentId('t1'),
      const GarmentId('b1'),
    });
    expect(
      result.days[1].candidate!.items.expand((i) => i.warnings),
      contains(isA<RotationExceeded>()),
    );
  });

  test('escolha fixada fica e conta como reserva', () {
    final result = plan(
      [
        g('t1', GarmentCategory.tShirt),
        g('t2', GarmentCategory.tShirt),
        g('b1', GarmentCategory.jeans),
        g('b2', GarmentCategory.jeans),
        g('s1', GarmentCategory.sneakers),
      ],
      [
        WeekDayRequest(
          day: day(9),
          pinned: const [
            OutfitItem(GarmentId('t1'), OutfitRole.mainTop),
            OutfitItem(GarmentId('b1'), OutfitRole.bottom),
          ],
        ),
        WeekDayRequest(day: day(10)),
      ],
    );
    expect(result.days.first.status, DayPlanStatus.pinned);
    expect(top(result.days.first), 't1');
    expect(top(result.days[1]), 't2', reason: 't1 está reservada na segunda');
  });

  test('dia fora da pesquisa e dia sem nada possível', () {
    final result = plan(
      [
        g('t1', GarmentCategory.tShirt),
        g('b1', GarmentCategory.jeans, availability: Availability.washing),
        g('s1', GarmentCategory.sneakers),
      ],
      [
        WeekDayRequest(day: day(14), include: false),
        WeekDayRequest(day: day(15)),
      ],
    );
    expect(result.days.first.status, DayPlanStatus.skipped);
    expect(result.days.first.items, isEmpty);
    final sunday = result.days[1];
    expect(sunday.status, DayPlanStatus.notFound);
    expect(
      sunday.gaps.map((g) => (g.role, g.cause)),
      contains((OutfitRole.bottom, GapCause.unavailable)),
      reason: 'a lavar: não se presume a lavagem',
    );
  });

  test('o mesmo pedido dá a mesma semana', () {
    final garments = [
      for (final t in ['t1', 't2', 't3', 't4']) g(t, GarmentCategory.tShirt),
      for (final b in ['b1', 'b2']) g(b, GarmentCategory.jeans),
      g('s1', GarmentCategory.sneakers),
    ];
    List<String?> tops() => plan(garments, week()).days.map(top).toList();
    expect(tops(), tops());
  });
}
