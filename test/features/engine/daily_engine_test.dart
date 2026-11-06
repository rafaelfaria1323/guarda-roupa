import 'package:flutter_test/flutter_test.dart';
import 'package:guarda_roupa/features/engine/domain/comfort.dart';
import 'package:guarda_roupa/features/engine/domain/daily_engine.dart';
import 'package:guarda_roupa/features/engine/domain/suggestion.dart';
import 'package:guarda_roupa/features/inspirations/domain/style_preference.dart';
import 'package:guarda_roupa/features/outfits/domain/outfit.dart';
import 'package:guarda_roupa/features/wardrobe/domain/availability.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment_attributes.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment_category.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment_color.dart';
import 'package:guarda_roupa/features/wear/domain/calendar_day.dart';
import 'package:guarda_roupa/features/wear/domain/wear_event.dart';

final _t0 = DateTime.utc(2026);

Garment g(
  String id,
  GarmentCategory category, {
  Warmth? warmth,
  Set<Occasion> occasions = const {},
  Availability availability = Availability.available,
  bool archived = false,
  bool? rainOk,
  bool? windOk,
  int? rgb,
  GarmentPattern? pattern,
  Formality? formality,
}) => Garment(
  id: GarmentId(id),
  category: category,
  availability: availability,
  createdAt: _t0,
  updatedAt: _t0,
  archivedAt: archived ? _t0 : null,
  colors: [if (rgb != null) GarmentColor.create(rgb: rgb, proportion: 1)!],
  attributes: GarmentAttributes(
    warmth: warmth,
    occasions: occasions,
    rainOk: rainOk,
    windOk: windOk,
    pattern: pattern,
    formality: formality,
  ),
);

CalendarDay day(int d) => CalendarDay(2026, 11, d);

WearEvent wore(int d, List<String> ids) => WearEvent(
  id: 'w$d${ids.join()}',
  wornOn: day(d),
  garmentIds: [for (final i in ids) GarmentId(i)],
  createdAt: DateTime.utc(2026, 11, d, 12),
);

StylePreference pref(
  PreferenceSubject subject,
  String value,
  PreferenceStance stance, {
  Set<Occasion> occasions = const {},
}) => StylePreference(
  id: 'p$value',
  subject: subject,
  value: value,
  stance: stance,
  occasions: occasions,
  createdAt: _t0,
  updatedAt: _t0,
);

SuggestionResult run(
  List<Garment> garments, {
  List<WearEvent> wears = const [],
  List<StylePreference> preferences = const [],
  Occasion? occasion,
  WeatherConditions? weather,
  int seed = 0,
  int today = 10,
}) => DailyEngine.suggest(
  WardrobeSnapshot(garments: garments, wears: wears, preferences: preferences),
  SuggestionRequest(
    day: day(today),
    occasion: occasion,
    weather: weather,
    seed: seed,
  ),
);

List<String> ids(OutfitCandidate c) => [
  for (final i in c.items) i.garment.id.value,
];

Map<String, OutfitRole> roles(OutfitCandidate c) => {
  for (final i in c.items) i.garment.id.value: i.role,
};

List<SuggestionNote> notesOf(OutfitCandidate c, String id) =>
    c.items.firstWhere((i) => i.garment.id.value == id).notes;

const hot = WeatherConditions(feelsLikeC: 26);
const mild = WeatherConditions(feelsLikeC: 18);
const cold = WeatherConditions(feelsLikeC: 8);

void main() {
  final tee = g('tee', GarmentCategory.tShirt, warmth: Warmth.light);
  final jeans = g('jeans', GarmentCategory.jeans, warmth: Warmth.medium);
  final sneakers = g('sneakers', GarmentCategory.sneakers);
  final basics = [tee, jeans, sneakers];

  group('modelos', () {
    test('t-shirt como top único: top + parte de baixo + calçado', () {
      final r = run(basics);
      expect(r.status, SuggestionStatus.valid);
      expect(r.candidates, hasLength(1));
      final c = r.candidates.single;
      expect(roles(c), {
        'tee': OutfitRole.mainTop,
        'jeans': OutfitRole.bottom,
        'sneakers': OutfitRole.footwear,
      });
      expect(c.isComplete, isTrue);
      expect(c.optionalLayer, isNull);
      expect(r.notes.single, isA<NoWeather>());
    });

    test('peça única + calçado', () {
      final r = run([g('dress', GarmentCategory.dress), sneakers]);
      expect(r.status, SuggestionStatus.valid);
      expect(roles(r.candidates.single), {
        'dress': OutfitRole.onePiece,
        'sneakers': OutfitRole.footwear,
      });
    });

    test('junta os dois modelos e nenhuma peça se repete', () {
      final r = run([
        ...basics,
        g('shirt', GarmentCategory.shirt),
        g('dress', GarmentCategory.dress),
      ]);
      expect(r.candidates, hasLength(3));
      for (final c in r.candidates) {
        expect(ids(c).toSet(), hasLength(ids(c).length));
      }
      final sets = r.candidates.map((c) => (ids(c)..sort()).join()).toSet();
      expect(sets, hasLength(3));
    });

    test('sem calçado: parcial e diz o que falta', () {
      final r = run([tee, jeans]);
      expect(r.status, SuggestionStatus.partial);
      final c = r.candidates.single;
      expect(c.isComplete, isFalse);
      expect(c.notes.whereType<MissingRole>().single.role, OutfitRole.footwear);
      expect(r.gaps.single.role, OutfitRole.footwear);
      expect(r.gaps.single.cause, GapCause.none);
    });

    test('guarda-roupa sem tops nem peças únicas: dados insuficientes', () {
      expect(run([]).status, SuggestionStatus.insufficientData);
      final r = run([jeans, sneakers]);
      expect(r.status, SuggestionStatus.insufficientData);
      expect(r.candidates, isEmpty);
      expect(
        r.gaps.map((x) => (x.role, x.cause)),
        containsAll([
          (OutfitRole.mainTop, GapCause.none),
          (OutfitRole.onePiece, GapCause.none),
        ]),
      );
    });
  });

  group('restrições obrigatórias', () {
    test('indisponíveis e arquivadas nunca são candidatas', () {
      final r = run([
        g('dirty', GarmentCategory.tShirt, availability: Availability.washing),
        g('old', GarmentCategory.tShirt, archived: true),
        ...basics,
      ]);
      for (final c in r.candidates) {
        expect(ids(c), isNot(contains('dirty')));
        expect(ids(c), isNot(contains('old')));
      }
    });

    test('todos os tops indisponíveis: nada encontrado, com o motivo', () {
      final r = run([
        g('dirty', GarmentCategory.tShirt, availability: Availability.drying),
        jeans,
        sneakers,
      ]);
      expect(r.status, SuggestionStatus.notFound);
      expect(
        r.gaps.firstWhere((x) => x.role == OutfitRole.mainTop).cause,
        GapCause.unavailable,
      );
    });

    test('ocasião: exclui peças de outras ocasiões, desconhecida entra '
        'com nota', () {
      final party = g(
        'party',
        GarmentCategory.top,
        occasions: {Occasion.evening},
      );
      final r = run([party, ...basics], occasion: Occasion.casual);
      expect(
        r.candidates.single.items.map((i) => i.garment.id.value),
        isNot(contains('party')),
      );
      expect(
        notesOf(r.candidates.single, 'tee'),
        contains(isA<OccasionUnknown>()),
      );

      final work = g(
        'work',
        GarmentCategory.shirt,
        occasions: {Occasion.workCasual},
      );
      final w = run([work, jeans, sneakers], occasion: Occasion.workCasual);
      expect(
        notesOf(w.candidates.single, 'work').whereType<OccasionMatches>(),
        hasLength(1),
      );

      final none = run([party, jeans, sneakers], occasion: Occasion.casual);
      expect(none.status, SuggestionStatus.notFound);
      expect(
        none.gaps.firstWhere((x) => x.role == OutfitRole.mainTop).cause,
        GapCause.otherOccasions,
      );
    });
  });

  group('rotatividade e lavagem', () {
    final shirt = g('shirt', GarmentCategory.shirt);

    test('peça dentro do intervalo vai para trás', () {
      final r = run(
        [tee, shirt, jeans, sneakers],
        wears: [
          wore(9, ['tee']),
        ],
      );
      expect(roles(r.candidates.first)['shirt'], OutfitRole.mainTop);
      final second = r.candidates[1];
      expect(
        notesOf(
          second,
          'tee',
        ).whereType<RotationExceeded>().single.eligibleFrom,
        day(12),
      );
    });

    test('sem alternativa elegível sugere na mesma, com aviso', () {
      final r = run(
        basics,
        wears: [
          wore(9, ['tee']),
        ],
      );
      expect(r.status, SuggestionStatus.valid);
      final item = r.candidates.single.items.first;
      expect(item.warnings.whereType<RotationExceeded>(), hasLength(1));
    });

    test('menos usadas primeiro, nunca usadas à frente', () {
      final r = run(
        [tee, shirt, jeans, sneakers],
        wears: [
          wore(1, ['shirt']),
        ],
      );
      expect(notesOf(r.candidates.first, 'tee'), contains(isA<NeverWorn>()));
      expect(
        notesOf(r.candidates[1], 'shirt').whereType<RecentUses>().single.times,
        1,
      );
    });

    test('lavagem recomendada só avisa', () {
      final r = run(
        basics,
        wears: [
          wore(1, ['tee']),
        ],
      );
      final notes = notesOf(r.candidates.single, 'tee');
      final wash = notes.whereType<WashRecommended>().single;
      expect((wash.uses, wash.threshold), (1, 1));
    });
  });

  group('preferências', () {
    test('gosto à frente, evito atrás; cores pelo RGB', () {
      final navy = g('navy', GarmentCategory.tShirt, rgb: 0x1F2A44);
      final striped = g(
        'striped',
        GarmentCategory.tShirt,
        pattern: GarmentPattern.stripes,
      );
      final r = run(
        [striped, tee, navy, jeans, sneakers],
        preferences: [
          pref(PreferenceSubject.color, '${0x1F2A44}', PreferenceStance.like),
          pref(PreferenceSubject.pattern, 'stripes', PreferenceStance.avoid),
        ],
      );
      final tops = [
        for (final c in r.candidates)
          c.items
              .firstWhere((i) => i.role == OutfitRole.mainTop)
              .garment
              .id
              .value,
      ];
      expect(tops, ['navy', 'tee', 'striped']);
      expect(
        notesOf(
          r.candidates.last,
          'striped',
        ).whereType<PreferenceMatch>().single.preference.stance,
        PreferenceStance.avoid,
      );
    });

    test('preferências de outra ocasião não contam', () {
      final navy = g('navy', GarmentCategory.tShirt, rgb: 0x1F2A44);
      final like = pref(
        PreferenceSubject.color,
        '${0x1F2A44}',
        PreferenceStance.like,
        occasions: {Occasion.evening},
      );
      final r = run([navy, jeans, sneakers], preferences: [like]);
      expect(
        notesOf(r.candidates.single, 'navy').whereType<PreferenceMatch>(),
        isEmpty,
      );
      final e = run(
        [navy, jeans, sneakers],
        preferences: [like],
        occasion: Occasion.evening,
      );
      expect(
        notesOf(e.candidates.single, 'navy').whereType<PreferenceMatch>(),
        hasLength(1),
      );
    });
  });

  group('conforto', () {
    final sweater = g('sweater', GarmentCategory.sweater, warmth: Warmth.warm);
    final coat = g('coat', GarmentCategory.coat);

    test('limites aprovados', () {
      const t = ComfortThresholds();
      ComfortBand b(double c) => t.bandFor(WeatherConditions(feelsLikeC: c));
      expect(b(22), ComfortBand.hot);
      expect(b(21.9), ComfortBand.mild);
      expect(b(14), ComfortBand.mild);
      expect(b(13.9), ComfortBand.cold);
      expect(
        t.isWindy(const WeatherConditions(feelsLikeC: 10, windKmh: 30)),
        isTrue,
      );
      expect(
        t.isWindy(const WeatherConditions(feelsLikeC: 10, windKmh: 29)),
        isFalse,
      );
    });

    test('calor: peça leve primeiro, sem camadas', () {
      final r = run([sweater, tee, jeans, sneakers, coat], weather: hot);
      final first = r.candidates.first;
      expect(ids(first), contains('tee'));
      expect(roles(first).values, isNot(contains(OutfitRole.outerLayer)));
      expect(first.optionalLayer, isNull);
      final mismatch = notesOf(
        r.candidates[1],
        'sweater',
      ).whereType<ComfortNote>().single;
      expect(mismatch.fit, ComfortFit.mismatch);
      expect(r.notes, isEmpty);
    });

    test('ameno: t-shirt chega, camada opcional à parte', () {
      final r = run([...basics, coat], weather: mild);
      final c = r.candidates.single;
      expect(roles(c).values, isNot(contains(OutfitRole.outerLayer)));
      expect(c.optionalLayer?.garment.id.value, 'coat');
      expect(c.optionalLayer?.notes.first, isA<OptionalLayerNote>());
    });

    test('frio: peça leve leva casaco; peça quente chega sozinha', () {
      final r = run([tee, sweater, jeans, sneakers, coat], weather: cold);
      final first = r.candidates.first;
      expect(ids(first), contains('sweater'));
      expect(roles(first).values, isNot(contains(OutfitRole.outerLayer)));
      final second = r.candidates[1];
      expect(roles(second)['coat'], OutfitRole.outerLayer);
      expect(ids(second), ['tee', 'coat', 'jeans', 'sneakers']);
    });

    test('frio sem casaco: peça quente à frente; só leve fica parcial', () {
      final r = run([tee, sweater, jeans, sneakers], weather: cold);
      expect(ids(r.candidates.first), contains('sweater'));

      final p = run(basics, weather: cold);
      expect(p.status, SuggestionStatus.partial);
      expect(
        p.candidates.single.notes.whereType<MissingRole>().single.role,
        OutfitRole.outerLayer,
      );
      expect(p.gaps.single.role, OutfitRole.outerLayer);
    });

    test('aquecimento desconhecido não exclui, diz-se', () {
      final plain = g('plain', GarmentCategory.tShirt);
      final r = run([plain, jeans, sneakers], weather: hot);
      expect(
        notesOf(
          r.candidates.single,
          'plain',
        ).whereType<ComfortNote>().single.fit,
        ComfortFit.unknown,
      );
    });

    test('chuva: prefere casaco e calçado marcados para chuva', () {
      final rainy = g('rainy', GarmentCategory.raincoat, rainOk: true);
      final jacket = g('jacket', GarmentCategory.jacket, rainOk: false);
      final boots = g('boots', GarmentCategory.boots, rainOk: true);
      final r = run([
        tee,
        jeans,
        sneakers,
        boots,
        jacket,
        rainy,
      ], weather: const WeatherConditions(feelsLikeC: 10, rain: true));
      final first = r.candidates.first;
      expect(roles(first)['rainy'], OutfitRole.outerLayer);
      expect(roles(first)['boots'], OutfitRole.footwear);
    });

    test('calor com chuva: oferece o impermeável como opcional', () {
      final rainy = g('rainy', GarmentCategory.raincoat, rainOk: true);
      final r = run([
        ...basics,
        rainy,
      ], weather: const WeatherConditions(feelsLikeC: 24, rain: true));
      expect(r.candidates.single.optionalLayer?.garment.id.value, 'rainy');
    });
  });

  group('determinismo', () {
    final many = [
      for (var i = 0; i < 6; i++) g('t$i', GarmentCategory.tShirt),
      jeans,
      sneakers,
    ];

    test('mesmo snapshot e seed: mesmo resultado', () {
      List<String> firstIds(int seed) => [
        for (final c in run(many, seed: seed).candidates) ...ids(c),
      ];
      expect(firstIds(7), firstIds(7));
    });

    test('a seed desempata entre peças equivalentes', () {
      final firsts = {
        for (var s = 0; s < 20; s++)
          ids(run(many, seed: s).candidates.first)[0],
      };
      expect(firsts.length, greaterThan(1));
    });
  });

  group('conjunto: cores e padrões', () {
    final white = g('white', GarmentCategory.tShirt, rgb: 0xFFFFFF);
    final red = g('red', GarmentCategory.tShirt, rgb: 0xC0392B);
    final black = g('black', GarmentCategory.trousers, rgb: 0x141414);
    final shoes = g('shoes', GarmentCategory.sneakers, rgb: 0xFFFFFF);

    String top(OutfitCandidate c) => c.items
        .firstWhere((i) => i.role == OutfitRole.mainTop)
        .garment
        .id
        .value;

    test('sem preferência: descreve, não ordena', () {
      final r = run([white, black, shoes]);
      final note = r.candidates.single.notes.whereType<ColorCombosNote>();
      expect(note.single.combos, {StyleCombo.neutralBase});
    });

    test('combinação preferida à frente, em qualquer seed', () {
      for (var seed = 0; seed < 6; seed++) {
        final like = run(
          [red, white, black, shoes],
          seed: seed,
          preferences: [
            pref(
              PreferenceSubject.combo,
              'neutral_base',
              PreferenceStance.like,
            ),
          ],
        );
        expect(like.candidates.map(top), ['white', 'red'], reason: '$seed');
        expect(
          like.candidates.first.notes.whereType<PreferenceMatch>(),
          hasLength(1),
        );
        // Já está na preferência: não se repete como descrição.
        expect(
          like.candidates.first.notes.whereType<ColorCombosNote>(),
          isEmpty,
        );

        final avoid = run(
          [white, red, black, shoes],
          seed: seed,
          preferences: [
            pref(
              PreferenceSubject.combo,
              'single_accent',
              PreferenceStance.avoid,
            ),
          ],
        );
        expect(avoid.candidates.map(top), ['white', 'red'], reason: '$seed');
      }
    });

    test('cor por indicar: a combinação não conta', () {
      final r = run(
        [tee, jeans, sneakers],
        preferences: [
          pref(PreferenceSubject.combo, 'neutral_base', PreferenceStance.like),
        ],
      );
      expect(r.candidates.single.notes.whereType<PreferenceMatch>(), isEmpty);
      expect(r.candidates.single.notes.whereType<ColorCombosNote>(), isEmpty);
    });

    test('dois padrões: atrás, com nota, nunca excluído', () {
      final striped = g(
        'striped',
        GarmentCategory.tShirt,
        pattern: GarmentPattern.stripes,
      );
      final plain = g(
        'plain',
        GarmentCategory.tShirt,
        pattern: GarmentPattern.plain,
      );
      final checked = g(
        'checked',
        GarmentCategory.trousers,
        pattern: GarmentPattern.checks,
      );
      for (var seed = 0; seed < 6; seed++) {
        final r = run([striped, plain, checked, sneakers], seed: seed);
        expect(r.candidates.map(top), ['plain', 'striped'], reason: '$seed');
        final mix = r.candidates.last.notes.whereType<SurfaceMixNote>().single;
        expect(mix.patterned, 2);
        expect(r.candidates.first.notes.whereType<SurfaceMixNote>(), isEmpty);
      }
    });
  });

  group('formalidade', () {
    final hoodie = g(
      'hoodie',
      GarmentCategory.tShirt,
      formality: Formality.relaxed,
    );
    final polo = g(
      'polo',
      GarmentCategory.tShirt,
      formality: Formality.smartCasual,
    );
    final tailored = g(
      'tailored',
      GarmentCategory.trousers,
      formality: Formality.dressy,
    );

    String top(OutfitCandidate c) => c.items
        .firstWhere((i) => i.role == OutfitRole.mainTop)
        .garment
        .id
        .value;

    test('descontraído com arranjado: atrás, com nota, nunca excluído', () {
      for (var seed = 0; seed < 6; seed++) {
        final r = run([hoodie, polo, tailored, sneakers], seed: seed);
        expect(r.candidates.map(top), ['polo', 'hoodie'], reason: '$seed');
        expect(
          r.candidates.last.notes.whereType<FormalityMixNote>(),
          hasLength(1),
        );
        expect(r.candidates.first.notes.whereType<FormalityMixNote>(), isEmpty);
      }
    });

    test('formalidade por indicar não conta como mistura', () {
      final r = run([hoodie, jeans, sneakers]);
      expect(r.candidates.single.notes.whereType<FormalityMixNote>(), isEmpty);
    });

    test('a preferência de formalidade conta em cada peça', () {
      for (var seed = 0; seed < 6; seed++) {
        final r = run(
          [hoodie, polo, jeans, sneakers],
          seed: seed,
          preferences: [
            pref(PreferenceSubject.formality, 'relaxed', PreferenceStance.like),
          ],
        );
        expect(r.candidates.map(top), ['hoodie', 'polo'], reason: '$seed');
        expect(
          r.candidates.first.items.first.notes.whereType<PreferenceMatch>(),
          hasLength(1),
        );
      }
    });
  });

  group('conjuntos guardados', () {
    // Ordem do motor: t1..t4 e b1..b4 (nunca usada, depois a mais antiga).
    final garments = [
      g('t1', GarmentCategory.shirt),
      g('t2', GarmentCategory.shirt),
      g('t3', GarmentCategory.shirt),
      g('t4', GarmentCategory.shirt),
      g('b1', GarmentCategory.trousers),
      g('b2', GarmentCategory.trousers),
      g('b3', GarmentCategory.trousers),
      g('b4', GarmentCategory.trousers),
      g('s1', GarmentCategory.sneakers),
    ];
    final wears = [
      wore(1, ['t2', 'b2']),
      wore(2, ['t3', 'b3']),
      wore(3, ['t4', 'b4']),
    ];
    Outfit saved(
      List<(String, OutfitRole)> items, {
      String? name,
      Set<Occasion> occasions = const {},
    }) => Outfit(
      id: 'o${items.map((i) => i.$1).join()}',
      name: name,
      occasions: occasions,
      items: [for (final (id, role) in items) OutfitItem(GarmentId(id), role)],
      createdAt: _t0,
      updatedAt: _t0,
    );
    SuggestionResult withOutfits(
      List<Outfit> outfits, {
      List<Garment>? pieces,
      Occasion? occasion,
    }) => DailyEngine.suggest(
      WardrobeSnapshot(
        garments: pieces ?? garments,
        wears: wears,
        outfits: outfits,
      ),
      SuggestionRequest(day: day(10), occasion: occasion),
    );

    test('um conjunto guardado é proposto e vem à frente', () {
      final mine = saved([
        ('t4', OutfitRole.mainTop),
        ('b1', OutfitRole.bottom),
        ('s1', OutfitRole.footwear),
      ], name: 'Sexta');
      expect(ids(run(garments, wears: wears).candidates.first), [
        't1',
        'b1',
        's1',
      ]);
      final r = withOutfits([mine]);
      final first = r.candidates.first;
      expect(ids(first), ['t4', 'b1', 's1']);
      expect(
        first.notes.whereType<SavedOutfitNote>().single.outfit.name,
        'Sexta',
      );
      expect(r.candidates, hasLength(3));
    });

    test('uma sugestão que já é um conjunto guardado fica marcada', () {
      final r = withOutfits([
        saved([('t1', OutfitRole.mainTop), ('b1', OutfitRole.bottom)]),
      ]);
      expect(ids(r.candidates.first), ['t1', 'b1', 's1']);
      expect(
        r.candidates.first.notes.whereType<SavedOutfitNote>(),
        hasLength(1),
      );
      expect(r.candidates[1].notes.whereType<SavedOutfitNote>(), isEmpty);
    });

    test('uma peça a lavar: o conjunto vem com outra no lugar dela', () {
      final mine = saved([
        ('t4', OutfitRole.mainTop),
        ('b4', OutfitRole.bottom),
      ], name: 'Sexta');
      Garment dirty(Garment x) =>
          g(x.id.value, x.category, availability: Availability.needsCleaning);
      final oneDirty = [
        for (final x in garments) x.id.value == 'b4' ? dirty(x) : x,
      ];
      final r = withOutfits([mine], pieces: oneDirty);
      final first = r.candidates.first;
      // A melhor parte de baixo que não é do conjunto.
      expect(ids(first), ['t4', 'b1', 's1']);
      final note = first.notes.whereType<SavedOutfitNote>().single;
      expect(note.outfit.name, 'Sexta');
      expect(note.swaps.single.role, OutfitRole.bottom);
      expect(note.swaps.single.removed?.id.value, 'b4');
      expect(note.swaps.single.added.id.value, 'b1');

      // Duas peças em falta já não é o mesmo conjunto.
      final twoDirty = [
        for (final x in garments)
          const {'t4', 'b4'}.contains(x.id.value) ? dirty(x) : x,
      ];
      expect(
        withOutfits(
          [mine],
          pieces: twoDirty,
        ).candidates.expand((c) => c.notes).whereType<SavedOutfitNote>(),
        isEmpty,
      );

      // Calçado apagado: entra o melhor que houver.
      final shoes = saved([
        ('t4', OutfitRole.mainTop),
        ('b4', OutfitRole.bottom),
        ('gone', OutfitRole.footwear),
      ]);
      final withShoes = withOutfits([shoes]).candidates.first;
      expect(ids(withShoes), ['t4', 'b4', 's1']);
      final swap = withShoes.notes
          .whereType<SavedOutfitNote>()
          .single
          .swaps
          .single;
      expect(swap.removed, isNull);
      expect(swap.added.id.value, 's1');
    });

    test('de outra ocasião, o conjunto não entra', () {
      final evening = saved(
        [('t4', OutfitRole.mainTop), ('b4', OutfitRole.bottom)],
        occasions: {Occasion.evening},
      );
      final work = withOutfits([evening], occasion: Occasion.workCasual);
      expect(
        work.candidates.expand((c) => c.notes).whereType<SavedOutfitNote>(),
        isEmpty,
      );
      final out = withOutfits([evening], occasion: Occasion.evening);
      expect(ids(out.candidates.first), ['t4', 'b4', 's1']);
    });

    test('não passa à frente de avisos (rotatividade)', () {
      final mine = saved([
        ('t4', OutfitRole.mainTop),
        ('b1', OutfitRole.bottom),
      ]);
      final r = DailyEngine.suggest(
        WardrobeSnapshot(
          garments: garments,
          wears: [
            ...wears,
            wore(9, ['t4']),
          ],
          outfits: [mine],
        ),
        SuggestionRequest(day: day(10)),
      );
      expect(ids(r.candidates.first), isNot(contains('t4')));
    });
  });
}
