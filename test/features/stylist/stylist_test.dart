import 'package:flutter_test/flutter_test.dart';
import 'package:guarda_roupa/features/engine/domain/comfort.dart';
import 'package:guarda_roupa/features/engine/domain/suggestion.dart';
import 'package:guarda_roupa/features/inspirations/domain/inspiration.dart';
import 'package:guarda_roupa/features/inspirations/domain/style_preference.dart';
import 'package:guarda_roupa/features/outfits/domain/outfit.dart';
import 'package:guarda_roupa/features/stylist/domain/stylist.dart';
import 'package:guarda_roupa/features/wardrobe/domain/availability.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment_attributes.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment_category.dart';
import 'package:guarda_roupa/features/wardrobe/domain/reference_color.dart';

import '../engine/daily_engine_test.dart' show day, g, pref, wore;

void main() {
  final garments = [
    g('tee', GarmentCategory.tShirt, rgb: ReferenceColor.white.rgb),
    g('shirt', GarmentCategory.shirt, formality: Formality.smartCasual),
    g('sweater', GarmentCategory.sweater),
    g('jeans', GarmentCategory.jeans, pattern: GarmentPattern.plain),
    g('dress', GarmentCategory.dress),
    g('shoes', GarmentCategory.sneakers),
    g(
      'dirty',
      GarmentCategory.trousers,
      availability: Availability.needsCleaning,
    ),
    g('old', GarmentCategory.coat, archived: true),
  ];
  final snapshot = WardrobeSnapshot(
    garments: garments,
    wears: [
      wore(8, ['tee', 'jeans']),
      wore(9, ['tee']),
    ],
    preferences: [
      pref(
        PreferenceSubject.color,
        '${ReferenceColor.navy.rgb}',
        PreferenceStance.like,
      ),
      pref(PreferenceSubject.pattern, 'floral', PreferenceStance.avoid),
    ],
  );
  final request = SuggestionRequest(
    day: day(10),
    occasion: Occasion.workCasual,
    weather: const WeatherConditions(
      feelsLikeC: 12.4,
      rain: true,
      windKmh: 20,
      sunny: false,
    ),
  );

  StylistBrief brief({String? ask, List<GarmentId> previous = const []}) =>
      StylistBrief.build(snapshot, request, ask: ask, previous: previous);

  String short(StylistBrief b, String id) =>
      b.ids.entries.firstWhere((e) => e.value == GarmentId(id)).key;

  test('o pedido leva só peças disponíveis, em texto e com ids curtos', () {
    final b = brief(ask: '  mais arranjado ', previous: [GarmentId('tee')]);
    final json = b.json;
    final sent = json['garments']! as List;
    expect(sent, hasLength(6));
    expect(b.ids.values, isNot(contains(GarmentId('dirty'))));
    expect(b.ids.values, isNot(contains(GarmentId('old'))));
    expect(b.ids.keys, everyElement(matches(r'^p\d+$')));
    // As menos usadas primeiro; a t-shirt (2 vezes) fica no fim.
    expect(b.ids.values.last, GarmentId('tee'));
    final tee = sent.last as Map;
    expect(tee['category'], GarmentCategory.tShirt.id);
    expect(tee['colors'], [ReferenceColor.white.id]);
    expect(tee['wears_30d'], 2);
    expect(tee['last_worn_days'], 1);
    expect(json['occasion'], Occasion.workCasual.id);
    expect(json['weather'], {
      'feels_like_c': 12,
      'rain': true,
      'wind_kmh': 20,
      'sunny': false,
    });
    expect(json['likes'], ['color ${ReferenceColor.navy.id}']);
    expect(json['avoids'], ['pattern floral']);
    expect(json['previous'], [short(b, 'tee')]);
    expect(json['ask'], 'mais arranjado');
    expect(brief(ask: '   ').json['ask'], isNull);
    expect(b.isEnough, isTrue);
  });

  test('leva as inspirações e, com um look alvo, a ocasião dele', () {
    Inspiration insp(String id, {Set<Occasion> occasions = const {}}) =>
        Inspiration(
          id: id,
          title: 'Look $id',
          sourceUrl: 'https://exemplo.pt/$id',
          notes: 'privado',
          palette: [ReferenceColor.navy.rgb],
          formality: Formality.dressy,
          occasions: occasions,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        );
    final all = [
      for (var i = 0; i < 25; i++) insp('i$i'),
      insp('night', occasions: {Occasion.evening}),
    ];
    final plain = StylistBrief.build(snapshot, request, inspirations: all);
    final sent = plain.json['inspirations']! as List;
    expect(sent, hasLength(StylistBrief.maxInspirations));
    expect(sent.first, {
      'title': 'Look i0',
      'palette': [ReferenceColor.navy.id],
      'formality': Formality.dressy.id,
      'patterns': <Object>[],
      'textures': <Object>[],
      'occasions': <Object>[],
      'proportions': <Object>[],
    });
    expect(plain.json['target'], isNull);
    expect(plain.json['occasion'], Occasion.workCasual.id);
    expect(plain.json.toString(), isNot(contains('privado')));
    expect(plain.json.toString(), isNot(contains('exemplo.pt')));

    final look = StylistBrief.build(
      snapshot,
      request,
      inspirations: [all.last, ...all.take(3)],
      target: all.last,
    );
    expect((look.json['target']! as Map)['title'], 'Look night');
    expect(look.json['inspirations']! as List, hasLength(3));
    expect(look.json['occasion'], Occasion.evening.id);
  });

  test('a resposta só vale com peças mandadas e papéis certos', () {
    final b = brief();
    StylistPick? review(List<(String, String)> items) => reviewStylistReply(
      StylistReply(items: items, name: 'Casual', why: 'Porque sim.'),
      b,
      snapshot,
      request,
    );

    final pick = review([
      (short(b, 'shirt'), 'main_top'),
      (short(b, 'sweater'), 'main_top'), // segundo top → camada
      (short(b, 'jeans'), 'footwear'), // papel errado → o certo
      (short(b, 'shoes'), 'footwear'),
      ('p999', 'bottom'), // não foi mandada
      (short(b, 'shirt'), 'main_top'), // repetida
    ])!;
    expect(
      [for (final i in pick.candidate.items) (i.garment.id.value, i.role)],
      [
        ('shirt', OutfitRole.mainTop),
        ('sweater', OutfitRole.midLayer),
        ('jeans', OutfitRole.bottom),
        ('shoes', OutfitRole.footwear),
      ],
    );
    expect(pick.name, 'Casual');
    expect(pick.why, 'Porque sim.');
    expect(pick.candidate.notes, isEmpty);

    // Só uma camada: passa a ser o top; sem calçado, avisa.
    final noShoes = review([
      (short(b, 'sweater'), 'mid_layer'),
      (short(b, 'jeans'), 'bottom'),
    ])!;
    expect(noShoes.candidate.items.first.role, OutfitRole.mainTop);
    expect(noShoes.candidate.notes, [const MissingRole(OutfitRole.footwear)]);

    // Vestido sozinho serve; com calças, ou sem parte de baixo, não.
    expect(review([(short(b, 'dress'), 'one_piece')]), isNotNull);
    expect(
      review([(short(b, 'dress'), 'one_piece'), (short(b, 'jeans'), 'bottom')]),
      isNull,
    );
    expect(review([(short(b, 'tee'), 'main_top')]), isNull);
  });

  test('lê a resposta do servidor', () {
    final r = StylistReply.fromJson({
      'name': 'Sexta',
      'why': 'Leve.',
      'items': [
        {'id': 'p1', 'role': 'main_top'},
        {'id': 2, 'role': 'bottom'},
        'x',
      ],
    });
    expect(r.items, [('p1', 'main_top')]);
    expect(r.name, 'Sexta');
    expect(StylistReply.fromJson({}).items, isEmpty);
  });
}
