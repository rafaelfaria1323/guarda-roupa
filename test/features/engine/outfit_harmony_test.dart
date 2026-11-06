import 'package:flutter_test/flutter_test.dart';
import 'package:guarda_roupa/features/engine/domain/outfit_harmony.dart';
import 'package:guarda_roupa/features/inspirations/domain/style_preference.dart';
import 'package:guarda_roupa/features/outfits/domain/outfit.dart';
import 'package:guarda_roupa/features/wardrobe/domain/availability.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment_attributes.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment_category.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment_color.dart';
import 'package:guarda_roupa/features/wardrobe/domain/reference_color.dart';

final _t0 = DateTime.utc(2026);

Garment g(
  String id, {
  List<(ReferenceColor, double)> colors = const [],
  GarmentPattern? pattern,
  SurfaceTexture? texture,
}) => Garment(
  id: GarmentId(id),
  category: GarmentCategory.tShirt,
  availability: Availability.available,
  createdAt: _t0,
  updatedAt: _t0,
  colors: [
    for (final (c, p) in colors)
      GarmentColor.create(rgb: c.rgb, proportion: p)!,
  ],
  attributes: GarmentAttributes(pattern: pattern, texture: texture),
);

Garment one(String id, ReferenceColor c) => g(id, colors: [(c, 1)]);

void main() {
  group('neutras', () {
    test('lista de referência', () {
      expect(OutfitHarmony.isNeutral(ReferenceColor.navy.rgb), isTrue);
      expect(OutfitHarmony.isNeutral(ReferenceColor.beige.rgb), isTrue);
      expect(OutfitHarmony.isNeutral(ReferenceColor.red.rgb), isFalse);
      expect(OutfitHarmony.isNeutral(ReferenceColor.olive.rgb), isFalse);
      expect(OutfitHarmony.isNeutral(ReferenceColor.silver.rgb), isTrue);
      expect(OutfitHarmony.isNeutral(ReferenceColor.gold.rgb), isTrue);
      expect(OutfitHarmony.isNeutral(ReferenceColor.mint.rgb), isFalse);
    });

    test('fora da lista: pelo croma', () {
      expect(OutfitHarmony.isNeutral(0x808080), isTrue);
      expect(OutfitHarmony.isNeutral(0x00C853), isFalse);
    });
  });

  group('combinações de cor', () {
    test('base neutra', () {
      expect(
        OutfitHarmony.combos([
          (one('tee', ReferenceColor.white), OutfitRole.mainTop),
          (one('trousers', ReferenceColor.black), OutfitRole.bottom),
          (one('sneakers', ReferenceColor.white), OutfitRole.footwear),
        ]),
        {StyleCombo.neutralBase, StyleCombo.highContrast},
      );
    });

    test('um só destaque, mesmo no calçado', () {
      expect(
        OutfitHarmony.combos([
          (one('tee', ReferenceColor.white), OutfitRole.mainTop),
          (one('trousers', ReferenceColor.black), OutfitRole.bottom),
          (one('sneakers', ReferenceColor.red), OutfitRole.footwear),
        ]),
        {
          StyleCombo.neutralBase,
          StyleCombo.singleAccent,
          StyleCombo.highContrast,
        },
      );
      expect(
        OutfitHarmony.combos([
          (one('tee', ReferenceColor.red), OutfitRole.mainTop),
          (one('trousers', ReferenceColor.black), OutfitRole.bottom),
          (one('sneakers', ReferenceColor.white), OutfitRole.footwear),
        ]),
        {StyleCombo.singleAccent},
      );
    });

    test('uma risca pequena não é destaque', () {
      final tee = g(
        'tee',
        colors: [(ReferenceColor.white, 0.9), (ReferenceColor.red, 0.1)],
      );
      expect(
        OutfitHarmony.combos([
          (tee, OutfitRole.mainTop),
          (one('trousers', ReferenceColor.black), OutfitRole.bottom),
        ]),
        {StyleCombo.neutralBase, StyleCombo.highContrast},
      );
    });

    test('tons próximos', () {
      expect(
        OutfitHarmony.combos([
          (one('shirt', ReferenceColor.lightBlue), OutfitRole.mainTop),
          (one('jeans', ReferenceColor.denim), OutfitRole.bottom),
        ]),
        contains(StyleCombo.tonal),
      );
      expect(
        OutfitHarmony.combos([
          (one('shirt', ReferenceColor.red), OutfitRole.mainTop),
          (one('jeans', ReferenceColor.denim), OutfitRole.bottom),
        ]),
        isNot(contains(StyleCombo.tonal)),
      );
      // Preto e branco não têm matiz: não são "tons próximos".
      expect(
        OutfitHarmony.combos([
          (one('tee', ReferenceColor.white), OutfitRole.mainTop),
          (one('trousers', ReferenceColor.black), OutfitRole.bottom),
        ]),
        isNot(contains(StyleCombo.tonal)),
      );
    });

    test('contraste: claro com escuro, suave ou nenhum', () {
      Set<StyleCombo>? pair(ReferenceColor top, ReferenceColor bottom) =>
          OutfitHarmony.combos([
            (one('top', top), OutfitRole.mainTop),
            (one('bottom', bottom), OutfitRole.bottom),
          ]);
      expect(
        pair(ReferenceColor.beige, ReferenceColor.navy),
        contains(StyleCombo.highContrast),
      );
      expect(
        pair(ReferenceColor.grey, ReferenceColor.black),
        contains(StyleCombo.highContrast),
      );
      expect(
        pair(ReferenceColor.beige, ReferenceColor.khaki),
        contains(StyleCombo.lowContrast),
      );
      expect(
        pair(ReferenceColor.navy, ReferenceColor.black),
        contains(StyleCombo.lowContrast),
      );
      // Branco com ganga fica no meio: nem uma coisa nem outra.
      final mid = pair(ReferenceColor.white, ReferenceColor.denim)!;
      expect(mid, isNot(contains(StyleCombo.highContrast)));
      expect(mid, isNot(contains(StyleCombo.lowContrast)));
    });

    test('contraste só entre peças grandes', () {
      final c = OutfitHarmony.combos([
        (one('tee', ReferenceColor.beige), OutfitRole.mainTop),
        (one('trousers', ReferenceColor.khaki), OutfitRole.bottom),
        (one('sneakers', ReferenceColor.black), OutfitRole.footwear),
      ])!;
      expect(c, contains(StyleCombo.lowContrast));
      expect(c, isNot(contains(StyleCombo.highContrast)));
    });

    test('cor por indicar numa peça: não se sabe', () {
      expect(
        OutfitHarmony.combos([
          (one('tee', ReferenceColor.white), OutfitRole.mainTop),
          (g('trousers'), OutfitRole.bottom),
        ]),
        isNull,
      );
    });
  });

  test('padrões e texturas fortes a competir', () {
    final s = OutfitHarmony.surface([
      g('a', pattern: GarmentPattern.stripes),
      g('b', pattern: GarmentPattern.checks, texture: SurfaceTexture.fuzzy),
      g('c', pattern: GarmentPattern.plain, texture: SurfaceTexture.knit),
      g('d'),
    ]);
    expect(s, (patterned: 2, textured: 1));
    expect(OutfitHarmony.load(s), 1);
    expect(OutfitHarmony.load((patterned: 1, textured: 1)), 0);
    expect(OutfitHarmony.load((patterned: 3, textured: 2)), 3);
  });
}
