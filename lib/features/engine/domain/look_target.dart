import '../../inspirations/domain/inspiration.dart';
import '../../wardrobe/domain/garment.dart';
import '../../wardrobe/domain/garment_attributes.dart';
import '../../wardrobe/domain/garment_category.dart';
import '../../wardrobe/domain/oklab.dart';

/// O que uma peça tem em comum com a inspiração.
enum LookAspect { color, formality, pattern, texture, image }

/// "Montar com o que tenho" (docs/features/inspiracoes-e-estilo.md): o
/// visual de uma inspiração como alvo do motor do dia. Só ordena peças que
/// existem; a inspiração nunca é posse.
///
/// As etiquetas são as que o utilizador confirmou. [similar] são as peças
/// que o FashionCLIP achou mais parecidas com a imagem, neste dispositivo
/// ([LookTarget.similarFrom]). As proporções ainda não contam: as peças
/// não têm o corte indicado.
final class LookTarget {
  const LookTarget({
    this.palette = const [],
    this.formality,
    this.patterns = const {},
    this.textures = const {},
    this.similar = const {},
  });

  factory LookTarget.fromInspiration(
    Inspiration i, {
    Set<GarmentId> similar = const {},
  }) => LookTarget(
    palette: i.palette,
    formality: i.formality,
    patterns: i.patterns,
    textures: i.textures,
    similar: similar,
  );

  /// Distância OKLab até à qual uma cor da peça conta como a da paleta
  /// (ex.: azul-marinho e um azul-escuro quase igual; não azul e denim).
  static const colorDistance = 0.08;

  /// Uma cor só conta se ocupar isto da peça (um pormenor não chega).
  static const significantProportion = 0.25;

  /// Das peças mais parecidas com a imagem, contam as [similarOverall]
  /// primeiras, no máximo [similarPerGroup] de cada grupo (tops, partes de
  /// baixo, calçado…). Assim um grupo que a imagem não mostra não ganha
  /// peças "parecidas" só por ser o melhor que há.
  static const similarOverall = 8;
  static const similarPerGroup = 2;

  final List<int> palette;
  final Formality? formality;
  final Set<GarmentPattern> patterns;
  final Set<SurfaceTexture> textures;
  final Set<GarmentId> similar;

  /// Sem nada para procurar: o resultado seria o do dia.
  bool get isEmpty =>
      palette.isEmpty &&
      formality == null &&
      patterns.isEmpty &&
      textures.isEmpty &&
      similar.isEmpty;

  /// O que a peça tem da inspiração. Atributo por indicar não conta.
  Set<LookAspect> aspectsOf(Garment g) => {
    if (_colorMatches(g)) LookAspect.color,
    if (formality case final f? when g.attributes.formality == f)
      LookAspect.formality,
    if (g.attributes.pattern case final p? when patterns.contains(p))
      LookAspect.pattern,
    if (g.attributes.texture case final t? when textures.contains(t))
      LookAspect.texture,
    if (similar.contains(g.id)) LookAspect.image,
  };

  bool _colorMatches(Garment g) {
    if (palette.isEmpty) return false;
    final targets = [for (final rgb in palette) Oklab.fromRgb(rgb)];
    const max2 = colorDistance * colorDistance;
    return g.colors.any((c) {
      if (c.proportion < significantProportion) return false;
      final lab = Oklab.fromRgb(c.rgb);
      return targets.any((t) => t.distance2(lab) <= max2);
    });
  }

  /// As peças parecidas com a imagem, a partir da ordem do FashionCLIP
  /// (da mais para a menos parecida).
  static Set<GarmentId> similarFrom(List<Garment> ranked) {
    final perGroup = <CategoryGroup, int>{};
    final out = <GarmentId>{};
    for (final g in ranked.take(similarOverall)) {
      final n = perGroup[g.category.group] ?? 0;
      if (n >= similarPerGroup) continue;
      perGroup[g.category.group] = n + 1;
      out.add(g.id);
    }
    return out;
  }

  /// Ocasião a pedir ao motor: a da inspiração, se for só uma.
  static Occasion? occasionOf(Inspiration i) =>
      i.occasions.length == 1 ? i.occasions.single : null;
}
