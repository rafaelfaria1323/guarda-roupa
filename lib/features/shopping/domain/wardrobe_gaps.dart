import '../../inspirations/domain/inspiration.dart';
import '../../wardrobe/domain/garment.dart';
import '../../wardrobe/domain/garment_category.dart';
import '../../wardrobe/domain/oklab.dart';
import '../../wardrobe/domain/reference_color.dart';

/// Porque é que uma peça faria falta (docs/features/pecas-em-falta.md).
enum GapReason {
  /// Não há nenhuma peça deste tipo (parte de cima, de baixo, calçado,
  /// casaco).
  missingGroup,

  /// Neste tipo só há peças claras: falta uma escura.
  onlyLight,

  /// Neste tipo só há peças escuras: falta uma clara.
  onlyDark,

  /// Uma cor que se repete nas inspirações e que não tens em nenhuma peça.
  inspirationColor,

  /// Inspirações arranjadas e nenhuma peça arranjada deste tipo.
  inspirationDressy,

  /// Muitas partes de cima para poucas de baixo.
  fewBottoms,
}

/// Uma peça que faria falta, calculada no aparelho a partir das peças e
/// das inspirações. Nunca diz marcas: isso é do Gemini (opcional).
final class WardrobeGap {
  const WardrobeGap({
    required this.reason,
    this.group,
    this.color,
    this.inspirations = const [],
  });

  final GapReason reason;

  /// Tipo de peça; `null` = qualquer (ex.: uma cor das inspirações).
  final CategoryGroup? group;

  /// Cor que falta (para [GapReason.inspirationColor]); para claro/escuro,
  /// a sugerida (preto ou branco).
  final ReferenceColor? color;

  /// Títulos das inspirações que pedem isto.
  final List<String> inspirations;

  /// Chave estável para "Não me interessa".
  String get key => '${reason.name}:${group?.name ?? ''}:${color?.id ?? ''}';

  @override
  bool operator ==(Object other) =>
      other is WardrobeGap &&
      other.key == key &&
      other.inspirations.join('|') == inspirations.join('|');

  @override
  int get hashCode => key.hashCode;

  @override
  String toString() => 'WardrobeGap($key, $inspirations)';
}

/// Tipos que contam para um armário que se veste todos os dias.
const essentialGroups = [
  CategoryGroup.top,
  CategoryGroup.bottom,
  CategoryGroup.footwear,
  CategoryGroup.outerwear,
];

/// Procura faltas simples, por ordem de importância, até [max]. Só conta
/// peças não arquivadas (as que estão a lavar continuam a ser tuas).
List<WardrobeGap> findWardrobeGaps(
  List<Garment> garments,
  List<Inspiration> inspirations, {
  Set<String> dismissed = const {},
  int max = 6,
}) {
  final owned = [
    for (final g in garments)
      if (g.archivedAt == null) g,
  ];
  final byGroup = <CategoryGroup, List<Garment>>{};
  for (final g in owned) {
    (byGroup[g.category.group] ??= []).add(g);
  }
  final gaps = <WardrobeGap>[];

  // 1. Tipos sem nenhuma peça.
  for (final group in essentialGroups) {
    if ((byGroup[group] ?? const []).isEmpty &&
        !(group == CategoryGroup.bottom &&
            (byGroup[CategoryGroup.onePiece] ?? const []).isNotEmpty &&
            (byGroup[CategoryGroup.top] ?? const []).isEmpty)) {
      gaps.add(WardrobeGap(reason: GapReason.missingGroup, group: group));
    }
  }

  // 2. Cores das inspirações que não tens (as que mais se repetem primeiro).
  final ownedColors = {
    for (final g in owned)
      for (final c in g.colors) nearestReference(c.rgb),
  };
  final wanted = <ReferenceColor, List<String>>{};
  for (final (i, insp) in inspirations.indexed) {
    final title = insp.title ?? insp.sourceHost ?? '#${i + 1}';
    for (final rgb in insp.palette.toSet()) {
      final c = nearestReference(rgb);
      if (ownedColors.contains(c) || c.isMetallic) continue;
      final list = wanted[c] ??= [];
      if (!list.contains(title)) list.add(title);
    }
  }
  final colors = wanted.entries.toList()
    ..sort((a, b) => b.value.length.compareTo(a.value.length));
  for (final e in colors.take(3)) {
    gaps.add(
      WardrobeGap(
        reason: GapReason.inspirationColor,
        color: e.key,
        inspirations: e.value,
      ),
    );
  }

  // 3. Inspirações arranjadas sem peças arranjadas.
  final dressy = [
    for (final (i, insp) in inspirations.indexed)
      if (insp.formality == Formality.dressy)
        insp.title ?? insp.sourceHost ?? '#${i + 1}',
  ];
  if (dressy.isNotEmpty) {
    for (final group in [CategoryGroup.footwear, CategoryGroup.bottom]) {
      final list = byGroup[group] ?? const [];
      if (list.isNotEmpty &&
          !list.any((g) => g.attributes.formality == Formality.dressy)) {
        gaps.add(
          WardrobeGap(
            reason: GapReason.inspirationDressy,
            group: group,
            inspirations: dressy,
          ),
        );
      }
    }
  }

  // 4. Só claro ou só escuro no calçado, nas partes de baixo e nos casacos.
  for (final group in [
    CategoryGroup.footwear,
    CategoryGroup.bottom,
    CategoryGroup.outerwear,
  ]) {
    final tones = [
      for (final g in byGroup[group] ?? const <Garment>[])
        if (g.colors.isNotEmpty) Oklab.fromRgb(g.colors.first.rgb).l,
    ];
    if (tones.isEmpty) continue;
    if (tones.every((l) => l >= lightTone)) {
      gaps.add(
        WardrobeGap(
          reason: GapReason.onlyLight,
          group: group,
          color: ReferenceColor.black,
        ),
      );
    } else if (tones.every((l) => l <= darkTone) &&
        group != CategoryGroup.outerwear) {
      gaps.add(
        WardrobeGap(
          reason: GapReason.onlyDark,
          group: group,
          color: group == CategoryGroup.footwear
              ? ReferenceColor.white
              : ReferenceColor.beige,
        ),
      );
    }
  }

  // 5. Partes de cima a mais para as de baixo.
  final tops = (byGroup[CategoryGroup.top] ?? const []).length;
  final bottoms = (byGroup[CategoryGroup.bottom] ?? const []).length;
  if (bottoms > 0 && tops >= 4 * bottoms) {
    gaps.add(
      const WardrobeGap(
        reason: GapReason.fewBottoms,
        group: CategoryGroup.bottom,
      ),
    );
  }

  return [
    for (final g in gaps)
      if (!dismissed.contains(g.key)) g,
  ].take(max).toList();
}

/// Claro a partir daqui (Oklab L), escuro até [darkTone].
const lightTone = 0.75;
const darkTone = 0.45;

/// A cor de referência mais próxima de [rgb] (Oklab).
ReferenceColor nearestReference(int rgb) {
  if (ReferenceColor.fromRgb(rgb) case final exact?) return exact;
  final lab = Oklab.fromRgb(rgb);
  var best = ReferenceColor.values.first;
  var bestD = double.infinity;
  for (final c in ReferenceColor.values) {
    final d = lab.distance2(Oklab.fromRgb(c.rgb));
    if (d < bestD) {
      best = c;
      bestD = d;
    }
  }
  return best;
}
