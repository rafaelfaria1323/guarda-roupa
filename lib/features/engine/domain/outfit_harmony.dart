import 'dart:math' as math;

import '../../inspirations/domain/style_preference.dart';
import '../../outfits/domain/outfit.dart';
import '../../wardrobe/domain/garment.dart';
import '../../wardrobe/domain/garment_attributes.dart';
import '../../wardrobe/domain/reference_color.dart';

/// Leitura do conjunto como um todo: cores (P-21) e padrões/texturas.
///
/// Não é uma "verdade de moda" (docs/features/motor-de-combinacoes.md):
/// - as combinações de cor só ordenam quando o utilizador tem uma
///   preferência sobre elas; sem preferência, são só descritas;
/// - padrões e texturas fortes repetidos põem o conjunto atrás de outro
///   igual em tudo o resto, sem nunca o excluir.
///
/// Sem cores numa peça considerada, a combinação de cor fica por saber:
/// nunca se afirma nem se penaliza.
abstract final class OutfitHarmony {
  /// Cores de referência tratadas como neutras (proposta P-21). Fora da
  /// lista, uma cor é neutra se tiver croma OKLCH < [neutralChroma].
  static const neutralColors = {
    ReferenceColor.white,
    ReferenceColor.cream,
    ReferenceColor.beige,
    ReferenceColor.khaki,
    ReferenceColor.brown,
    ReferenceColor.grey,
    ReferenceColor.charcoal,
    ReferenceColor.black,
    ReferenceColor.navy,
    ReferenceColor.denim,
  };

  static const neutralChroma = 0.05;

  /// "Tons próximos": matizes a menos disto (graus OKLCH) e todas com cor.
  static const tonalHueDegrees = 30.0;
  static const _achromatic = 0.03;

  /// Uma cor só conta para "um só destaque" se ocupar isto da peça.
  static const significantProportion = 0.25;

  static const _bigRoles = {
    OutfitRole.mainTop,
    OutfitRole.bottom,
    OutfitRole.onePiece,
    OutfitRole.outerLayer,
    OutfitRole.midLayer,
  };

  static const strongTextures = {SurfaceTexture.textured, SurfaceTexture.fuzzy};

  /// As combinações de [StyleCombo] que o conjunto cumpre, ou `null` se
  /// faltar a cor de alguma peça.
  static Set<StyleCombo>? combos(List<(Garment, OutfitRole)> items) {
    if (items.isEmpty || items.any((i) => i.$1.colors.isEmpty)) return null;
    final big = [
      for (final (g, role) in items)
        if (_bigRoles.contains(role)) g,
    ];
    final out = <StyleCombo>{};

    if (big.isNotEmpty && big.every((g) => isNeutral(_dominant(g)))) {
      out.add(StyleCombo.neutralBase);
    }

    final accented = items.where(
      (i) => i.$1.colors.any(
        (c) => c.proportion >= significantProportion && !isNeutral(c.rgb),
      ),
    );
    if (items.length >= 2 && accented.length == 1) {
      out.add(StyleCombo.singleAccent);
    }

    if (big.length >= 2) {
      final lch = [for (final g in big) _oklch(_dominant(g))];
      if (lch.every((c) => c.chroma >= _achromatic)) {
        final hues = [for (final c in lch) c.hue];
        if (_hueSpread(hues) <= tonalHueDegrees) out.add(StyleCombo.tonal);
      }
    }
    return out;
  }

  /// Peças com padrão (não liso) e com textura forte. Padrão ou textura
  /// por indicar não conta.
  static ({int patterned, int textured}) surface(Iterable<Garment> items) {
    var patterned = 0;
    var textured = 0;
    for (final g in items) {
      final p = g.attributes.pattern;
      if (p != null && p != GarmentPattern.plain) patterned++;
      if (strongTextures.contains(g.attributes.texture)) textured++;
    }
    return (patterned: patterned, textured: textured);
  }

  /// Quanto o conjunto tem "a competir": cada padrão e cada textura forte
  /// além do primeiro. 0 = nada a competir.
  static int load(({int patterned, int textured}) s) =>
      math.max(0, s.patterned - 1) + math.max(0, s.textured - 1);

  static bool isNeutral(int rgb) {
    if (ReferenceColor.fromRgb(rgb) case final ref?) {
      return neutralColors.contains(ref);
    }
    return _oklch(rgb).chroma < neutralChroma;
  }

  static int _dominant(Garment g) =>
      g.colors.reduce((a, b) => b.proportion > a.proportion ? b : a).rgb;

  /// Menor arco que contém todas as matizes.
  static double _hueSpread(List<double> hues) {
    final sorted = [...hues]..sort();
    var largestGap = 360 - sorted.last + sorted.first;
    for (var i = 1; i < sorted.length; i++) {
      largestGap = math.max(largestGap, sorted[i] - sorted[i - 1]);
    }
    return 360 - largestGap;
  }

  /// sRGB → OKLCH (Björn Ottosson, 2020).
  static ({double lightness, double chroma, double hue}) _oklch(int rgb) {
    double lin(int c) {
      final v = c / 255;
      return v <= 0.04045
          ? v / 12.92
          : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    }

    final r = lin((rgb >> 16) & 0xFF);
    final g = lin((rgb >> 8) & 0xFF);
    final b = lin(rgb & 0xFF);
    double cbrt(double x) => math.pow(x, 1 / 3).toDouble();
    final l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b);
    final m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b);
    final s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b);
    final okL = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s;
    final okA = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s;
    final okB = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s;
    final hue = math.atan2(okB, okA) * 180 / math.pi;
    return (
      lightness: okL,
      chroma: math.sqrt(okA * okA + okB * okB),
      hue: hue < 0 ? hue + 360 : hue,
    );
  }
}
