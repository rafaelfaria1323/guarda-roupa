import 'package:flutter_test/flutter_test.dart';
import 'package:guarda_roupa/features/engine/domain/daily_engine.dart';
import 'package:guarda_roupa/features/engine/domain/look_target.dart';
import 'package:guarda_roupa/features/engine/domain/suggestion.dart';
import 'package:guarda_roupa/features/inspirations/domain/inspiration.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment_attributes.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment_category.dart';
import 'package:guarda_roupa/features/wardrobe/domain/reference_color.dart';
import 'package:guarda_roupa/features/wear/domain/wear_event.dart';

import 'daily_engine_test.dart' show day, g, ids, wore;

SuggestionResult runLook(
  List<Garment> garments,
  LookTarget look, {
  List<WearEvent> wears = const [],
}) => DailyEngine.suggest(
  WardrobeSnapshot(garments: garments, wears: wears),
  SuggestionRequest(day: day(10), look: look),
);

void main() {
  final navy = ReferenceColor.navy.rgb;
  final white = ReferenceColor.white.rgb;

  group('aspectsOf', () {
    test('cor parecida conta; outra cor ou cor por indicar não', () {
      final look = LookTarget(palette: [navy]);
      expect(look.aspectsOf(g('a', GarmentCategory.shirt, rgb: 0x1E2A46)), {
        LookAspect.color,
      });
      expect(
        look.aspectsOf(
          g('b', GarmentCategory.shirt, rgb: ReferenceColor.blue.rgb),
        ),
        isEmpty,
      );
      expect(look.aspectsOf(g('c', GarmentCategory.shirt)), isEmpty);
    });

    test('formalidade, padrão e imagem; desconhecido não conta', () {
      final look = LookTarget(
        formality: Formality.smartCasual,
        patterns: {GarmentPattern.stripes},
        similar: {const GarmentId('a')},
      );
      expect(
        look.aspectsOf(
          g(
            'a',
            GarmentCategory.shirt,
            formality: Formality.smartCasual,
            pattern: GarmentPattern.stripes,
          ),
        ),
        {LookAspect.formality, LookAspect.pattern, LookAspect.image},
      );
      expect(look.aspectsOf(g('b', GarmentCategory.shirt)), isEmpty);
    });

    test('fromInspiration usa as etiquetas confirmadas', () {
      final i = Inspiration(
        id: 'i',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        title: 'Azul',
        palette: [navy],
        formality: Formality.dressy,
        occasions: {Occasion.evening},
      );
      final look = LookTarget.fromInspiration(i);
      expect(look.palette, [navy]);
      expect(look.formality, Formality.dressy);
      expect(look.isEmpty, isFalse);
      expect(LookTarget.occasionOf(i), Occasion.evening);
      expect(
        LookTarget.occasionOf(
          Inspiration(
            id: 'j',
            createdAt: DateTime.utc(2026),
            updatedAt: DateTime.utc(2026),
            occasions: {Occasion.casual, Occasion.evening},
          ),
        ),
        isNull,
      );
    });
  });

  test('proporções: cada peça faz a sua parte; corte por indicar não', () {
    final look = LookTarget(proportions: {Proportion.fittedTopRelaxedBottom});
    Set<LookAspect> of(Garment x) => look.aspectsOf(x);
    expect(of(g('t', GarmentCategory.tShirt, fit: GarmentFit.fitted)), {
      LookAspect.proportion,
    });
    expect(of(g('j', GarmentCategory.jeans, fit: GarmentFit.relaxed)), {
      LookAspect.proportion,
    });
    expect(of(g('j2', GarmentCategory.jeans, fit: GarmentFit.fitted)), isEmpty);
    expect(of(g('t2', GarmentCategory.tShirt)), isEmpty);
    expect(
      of(g('s', GarmentCategory.sneakers, fit: GarmentFit.fitted)),
      isEmpty,
    );
    expect(
      LookTarget.proportionMatches(
        Proportion.croppedTop,
        g('c', GarmentCategory.tShirt, length: GarmentLength.cropped),
      ),
      isTrue,
    );
    expect(
      LookTarget.proportionMatches(
        Proportion.longLayer,
        g('c', GarmentCategory.coat, length: GarmentLength.long),
      ),
      isTrue,
    );
    expect(
      LookTarget.proportionMatches(
        Proportion.longLayer,
        g('t', GarmentCategory.tShirt, length: GarmentLength.long),
      ),
      isFalse,
    );
  });

  test('similarFrom: no máximo duas de cada grupo, das oito primeiras', () {
    final ranked = [
      for (var i = 0; i < 4; i++) g('t$i', GarmentCategory.tShirt),
      g('j0', GarmentCategory.jeans),
      for (var i = 0; i < 5; i++) g('s$i', GarmentCategory.sneakers),
    ];
    expect(
      {for (final id in LookTarget.similarFrom(ranked)) id.value},
      {'t0', 't1', 'j0', 's0', 's1'},
    );
  });

  group('motor com inspiração', () {
    final garments = [
      g('t-white', GarmentCategory.tShirt, rgb: white),
      g('t-navy', GarmentCategory.tShirt, rgb: navy),
      g('jeans', GarmentCategory.jeans),
      g('shoes', GarmentCategory.sneakers),
    ];

    test('a peça com a cor da inspiração passa à frente, com a nota', () {
      final whiteLook = runLook(garments, LookTarget(palette: [white]));
      expect(ids(whiteLook.candidates.first).first, 't-white');
      final look = runLook(garments, LookTarget(palette: [navy]));
      final first = look.candidates.first;
      expect(ids(first).first, 't-navy');
      expect(first.items.first.notes.whereType<LookMatch>().single.aspects, {
        LookAspect.color,
      });
    });

    test('a rotatividade continua antes da inspiração', () {
      final r = runLook(
        garments,
        LookTarget(palette: [navy]),
        wears: [
          wore(9, ['t-navy']),
        ],
      );
      expect(ids(r.candidates.first).first, 't-white');
    });

    test('as proporções ordenam pelo corte', () {
      final r = runLook([
        g('t-a', GarmentCategory.tShirt, fit: GarmentFit.relaxed),
        g('t-b', GarmentCategory.tShirt, fit: GarmentFit.fitted),
        g('jeans', GarmentCategory.jeans),
        g('shoes', GarmentCategory.sneakers),
      ], LookTarget(proportions: {Proportion.fittedTopRelaxedBottom}));
      expect(ids(r.candidates.first).first, 't-b');
    });

    test('a imagem conta como as etiquetas', () {
      final r = runLook(
        garments,
        LookTarget(similar: {const GarmentId('t-navy')}),
      );
      expect(ids(r.candidates.first).first, 't-navy');
    });
  });
}
