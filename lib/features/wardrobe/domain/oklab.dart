import 'dart:math' as math;

/// Cor no espaço OKLab (Björn Ottosson, 2020), para distâncias percetuais.
/// Proximidade aqui não quer dizer que duas cores combinam.
final class Oklab {
  const Oklab(this.l, this.a, this.b);

  factory Oklab.fromRgb(int rgb) {
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
    return Oklab(
      0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
      1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
      0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s,
    );
  }

  final double l;
  final double a;
  final double b;

  /// Croma (OKLCH).
  double get chroma => math.sqrt(a * a + b * b);

  /// Matiz em graus, [0, 360).
  double get hue {
    final h = math.atan2(b, a) * 180 / math.pi;
    return h < 0 ? h + 360 : h;
  }

  /// Distância ao quadrado (para comparar, sem raiz).
  double distance2(Oklab o) {
    final dl = l - o.l;
    final da = a - o.a;
    final db = b - o.b;
    return dl * dl + da * da + db * db;
  }
}
