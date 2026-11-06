import '../../../core/domain/result.dart';
import '../../inspirations/domain/inspiration.dart';
import '../../inspirations/domain/inspiration_brief.dart';
import '../../photo_ai/domain/photo_reader.dart';
import '../../wardrobe/domain/garment.dart';
import '../../wardrobe/domain/garment_category.dart';
import '../../wardrobe/domain/reference_color.dart';
import 'wardrobe_gaps.dart';

/// Ideias de compra do Gemini (docs/features/pecas-em-falta.md).
abstract interface class ShoppingAdvisor {
  Future<Result<List<ShoppingIdea>, PhotoReadFailure>> advise(
    Map<String, Object?> brief,
  );
}

/// Nível de preço da marca em relação às que a pessoa já tem.
enum BrandTier {
  same,
  cheaper,
  pricier;

  static BrandTier? fromId(Object? id) {
    for (final t in values) {
      if (t.name == id) return t;
    }
    return null;
  }
}

final class ShoppingBrand {
  const ShoppingBrand(this.name, this.tier);

  final String name;
  final BrandTier tier;
}

/// Uma peça a comprar: descrição, porquê, texto para pesquisar e marcas.
/// Nunca modelos nem preços (podiam ser inventados).
final class ShoppingIdea {
  const ShoppingIdea({
    required this.category,
    required this.title,
    required this.search,
    required this.brands,
    this.color,
    this.why,
  });

  /// `null` se a resposta não serve.
  static ShoppingIdea? fromJson(Object? raw) {
    if (raw is! Map<String, Object?>) return null;
    final id = raw['category'];
    final category = id is String ? GarmentCategory.fromId(id) : null;
    final title = raw['title'];
    final search = raw['search'];
    if (category == null || title is! String || search is! String) {
      return null;
    }
    final brands = [
      for (final b in raw['brands'] is List ? raw['brands']! as List : [])
        if (b case {'name': final String name, 'tier': final Object? tier})
          if (BrandTier.fromId(tier) case final t?) ShoppingBrand(name, t),
    ];
    if (brands.isEmpty) return null;
    return ShoppingIdea(
      category: category,
      color: ReferenceColor.values
          .where((c) => c.id == raw['color'])
          .firstOrNull,
      title: title,
      why: raw['why'] is String ? raw['why']! as String : null,
      search: search,
      brands: brands,
    );
  }

  final GarmentCategory category;
  final ReferenceColor? color;
  final String title;
  final String? why;
  final String search;
  final List<ShoppingBrand> brands;

  /// Chave para "Não me interessa".
  String get key => 'idea:${category.id}:${color?.id ?? ''}';

  /// Pesquisa na Web pela marca e pela descrição.
  Uri searchUri(ShoppingBrand brand) =>
      Uri.https('www.google.com', '/search', {'q': '${brand.name} $search'});
}

/// O que se manda ao Gemini: só texto. Peças (categoria, nome, marca,
/// cores, formalidade), etiquetas das inspirações (nunca imagens nem
/// links), as faltas encontradas no aparelho, o orçamento por peça e as
/// ideias postas de lado.
Map<String, Object?> shoppingBrief(
  List<Garment> garments,
  List<Inspiration> inspirations,
  List<WardrobeGap> gaps, {
  int? budgetEur,
  Set<String> dismissed = const {},
}) => {
  'kind': 'shopping',
  'garments': [
    for (final g in garments.where((g) => g.archivedAt == null).take(300))
      {
        'category': g.category.id,
        'name': ?g.name,
        'brand': ?g.brand,
        'formality': ?g.attributes.formality?.id,
        'colors': [
          for (final c in g.colors.take(3)) nearestReference(c.rgb).id,
        ],
      },
  ],
  'inspirations': [for (final i in inspirations.take(40)) inspirationBrief(i)],
  'gaps': [
    for (final g in gaps)
      {
        'reason': g.reason.name,
        'group': ?g.group?.name,
        'color': ?g.color?.id,
        'inspirations': g.inspirations.length,
      },
  ],
  'budget_eur': budgetEur,
  'dismissed': [
    for (final k in dismissed)
      if (k.startsWith('idea:')) k.substring(5),
  ],
};
