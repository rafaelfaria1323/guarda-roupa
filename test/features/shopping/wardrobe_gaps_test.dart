import 'package:flutter_test/flutter_test.dart';
import 'package:guarda_roupa/features/inspirations/domain/inspiration.dart';
import 'package:guarda_roupa/features/shopping/domain/shopping_advice.dart';
import 'package:guarda_roupa/features/shopping/domain/wardrobe_gaps.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment_category.dart';
import 'package:guarda_roupa/features/wardrobe/domain/reference_color.dart';

import '../engine/daily_engine_test.dart' show g;

Inspiration insp(
  String title, {
  List<int> palette = const [],
  Formality? formality,
}) => Inspiration(
  id: title,
  title: title,
  palette: palette,
  formality: formality,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

void main() {
  final white = ReferenceColor.white.rgb;
  final black = ReferenceColor.black.rgb;
  final navy = ReferenceColor.navy.rgb;

  test('sapatos só brancos: faltam uns escuros; sem casaco: falta', () {
    final gaps = findWardrobeGaps([
      g('t', GarmentCategory.tShirt, rgb: white),
      g('j', GarmentCategory.jeans, rgb: ReferenceColor.denim.rgb),
      g('s', GarmentCategory.sneakers, rgb: white),
      g('old', GarmentCategory.coat, archived: true),
    ], []);
    expect(
      [for (final x in gaps) x.key],
      ['missingGroup:outerwear:', 'onlyLight:footwear:black'],
    );
  });

  test('cores e formalidade das inspirações, por número de inspirações', () {
    final gaps = findWardrobeGaps(
      [
        g('t', GarmentCategory.sweatshirt, rgb: ReferenceColor.grey.rgb),
        g('j', GarmentCategory.trousers, rgb: black),
        g('s', GarmentCategory.sneakers, rgb: black),
        g('c', GarmentCategory.coat, rgb: black),
      ],
      [
        insp('A', palette: [navy, ReferenceColor.grey.rgb]),
        insp('B', palette: [navy, ReferenceColor.burgundy.rgb]),
        insp('C', formality: Formality.dressy),
      ],
      dismissed: {'inspirationColor::burgundy'},
    );
    expect(gaps, [
      const WardrobeGap(
        reason: GapReason.inspirationColor,
        color: ReferenceColor.navy,
        inspirations: ['A', 'B'],
      ),
      const WardrobeGap(
        reason: GapReason.inspirationDressy,
        group: CategoryGroup.footwear,
        inspirations: ['C'],
      ),
      const WardrobeGap(
        reason: GapReason.inspirationDressy,
        group: CategoryGroup.bottom,
        inspirations: ['C'],
      ),
      const WardrobeGap(
        reason: GapReason.onlyDark,
        group: CategoryGroup.footwear,
        color: ReferenceColor.white,
      ),
      const WardrobeGap(
        reason: GapReason.onlyDark,
        group: CategoryGroup.bottom,
        color: ReferenceColor.beige,
      ),
    ]);
  });

  test('muitas partes de cima para poucas de baixo', () {
    final gaps = findWardrobeGaps([
      for (var i = 0; i < 8; i++) g('t$i', GarmentCategory.tShirt),
      g('j', GarmentCategory.jeans),
      g('s', GarmentCategory.sneakers),
      g('c', GarmentCategory.coat),
    ], []);
    expect([for (final x in gaps) x.reason], [GapReason.fewBottoms]);
  });

  test('o pedido de compras leva marca e etiquetas, não notas nem links', () {
    final shoes = g('s', GarmentCategory.sneakers, rgb: white);
    final brief = shoppingBrief(
      [
        Garment(
          id: shoes.id,
          category: shoes.category,
          availability: shoes.availability,
          createdAt: shoes.createdAt,
          updatedAt: shoes.updatedAt,
          colors: shoes.colors,
          brand: 'Uniqlo',
          notes: 'segredo',
        ),
      ],
      [
        Inspiration(
          id: 'i',
          title: 'Preto',
          sourceUrl: 'https://pinterest.com/x',
          palette: [black],
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        ),
      ],
      const [
        WardrobeGap(
          reason: GapReason.onlyLight,
          group: CategoryGroup.footwear,
          color: ReferenceColor.black,
        ),
      ],
      budgetEur: 80,
      dismissed: {'idea:coat:navy', 'onlyLight:footwear:black'},
    );
    expect(brief, {
      'kind': 'shopping',
      'garments': [
        {
          'category': 'sneakers',
          'brand': 'Uniqlo',
          'colors': ['white'],
        },
      ],
      'inspirations': [
        {
          'title': 'Preto',
          'palette': ['black'],
          'patterns': <String>[],
          'textures': <String>[],
          'occasions': <String>[],
          'proportions': <String>[],
        },
      ],
      'gaps': [
        {
          'reason': 'onlyLight',
          'group': 'footwear',
          'color': 'black',
          'inspirations': 0,
        },
      ],
      'budget_eur': 80,
      'dismissed': ['coat:navy'],
    });
  });

  test('lê ideias e descarta as que não servem', () {
    final idea = ShoppingIdea.fromJson({
      'category': 'sneakers',
      'color': 'black',
      'title': 'Ténis pretos',
      'search': 'ténis pretos pele',
      'brands': [
        {'name': 'COS', 'tier': 'same'},
        {'name': 'X', 'tier': 'luxo'},
      ],
    })!;
    expect(idea.key, 'idea:sneakers:black');
    expect(
      [for (final b in idea.brands) (b.name, b.tier)],
      [('COS', BrandTier.same)],
    );
    expect(
      idea.searchUri(idea.brands.first).toString(),
      'https://www.google.com/search?q=COS+t%C3%A9nis+pretos+pele',
    );
    expect(
      ShoppingIdea.fromJson({
        'category': 'nave',
        'title': 'x',
        'search': 'x',
        'brands': [
          {'name': 'A', 'tier': 'same'},
        ],
      }),
      isNull,
    );
    expect(
      ShoppingIdea.fromJson({
        'category': 'jeans',
        'title': 'x',
        'search': 'x',
        'brands': <Object>[],
      }),
      isNull,
    );
  });
}
