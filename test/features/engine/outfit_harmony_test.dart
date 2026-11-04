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
        {StyleCombo.neutralBase},
      );
    });

    test('um só destaque, mesmo no calçado', () {
      expect(
        OutfitHarmony.combos([
          (one('tee', ReferenceColor.white), OutfitRole.mainTop),
          (one('trousers', ReferenceColor.black), OutfitRole.bottom),
          (one('sneakers', ReferenceColor.red), OutfitRole.footwear),
        ]),
        {StyleCombo.neutralBase, StyleCombo.singleAccent},
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
        {StyleCombo.neutralBase},
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
