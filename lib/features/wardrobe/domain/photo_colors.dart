import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'garment_color.dart';
import 'oklab.dart';
import 'reference_color.dart';

/// Cores sugeridas a partir de uma foto, sem modelo (baseline da IA local,
/// docs/features/ia-local.md). Cada píxel vai para a cor de referência mais
/// próxima em OKLab; o fundo estima-se pela borda da foto.
///
/// O resultado é sempre uma sugestão (`confirmed: false`): sombras, reflexos
/// e fundos parecidos com a peça enganam.
abstract final class PhotoColors {
  /// Lado máximo da imagem reduzida que se analisa.
  static const sampleSide = 64;

  /// A borda é fundo se uma só cor ocupar pelo menos isto dela.
  static const backgroundShare = 0.6;

  /// Sem o fundo, tem de sobrar isto da imagem; senão a peça é da cor do
  /// fundo (ou ocupa a foto toda) e o fundo não se tira.
  static const minForeground = 0.15;

  /// Uma cor entra se ocupar pelo menos isto do que sobra.
  static const minShare = 0.1;
  static const maxColors = 3;

  static final _refs = [
    for (final c in ReferenceColor.values) (c, Oklab.fromRgb(c.rgb)),
  ];

  /// `[]` se a imagem não se ler.
  static List<GarmentColor> suggest(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null || decoded.width == 0 || decoded.height == 0) {
      return const [];
    }
    final scale =
        sampleSide /
        (decoded.width > decoded.height ? decoded.width : decoded.height);
    final image = scale < 1
        ? img.copyResize(
            decoded,
            width: (decoded.width * scale).round().clamp(1, sampleSide),
            height: (decoded.height * scale).round().clamp(1, sampleSide),
            interpolation: img.Interpolation.average,
          )
        : decoded;

    final w = image.width;
    final h = image.height;
    final grid = List<ReferenceColor?>.filled(w * h, null);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final p = image.getPixel(x, y);
        if (p.a < p.maxChannelValue / 2) continue; // transparente
        final rgb = (p.r.toInt() << 16) | (p.g.toInt() << 8) | p.b.toInt();
        grid[y * w + x] = _nearest(rgb);
      }
    }

    // Fundo: a cor que domina a moldura exterior (1/10 de cada lado).
    final border = <ReferenceColor, int>{};
    var borderTotal = 0;
    final bx = (w / 10).ceil();
    final by = (h / 10).ceil();
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        if (x >= bx && x < w - bx && y >= by && y < h - by) continue;
        final c = grid[y * w + x];
        if (c == null) continue;
        border[c] = (border[c] ?? 0) + 1;
        borderTotal++;
      }
    }
    ReferenceColor? background;
    if (borderTotal > 0) {
      final top = border.entries.reduce((a, b) => b.value > a.value ? b : a);
      if (top.value / borderTotal >= backgroundShare) background = top.key;
    }

    Map<ReferenceColor, int> count({ReferenceColor? without}) {
      final out = <ReferenceColor, int>{};
      for (final c in grid) {
        if (c == null || c == without) continue;
        out[c] = (out[c] ?? 0) + 1;
      }
      return out;
    }

    final all = count();
    final total = all.values.fold(0, (s, v) => s + v);
    if (total == 0) return const [];
    var counts = all;
    if (background != null) {
      final rest = count(without: background);
      final kept = rest.values.fold(0, (s, v) => s + v);
      if (kept / total >= minForeground) counts = rest;
    }
    return _proportions(counts);
  }

  static ReferenceColor _nearest(int rgb) {
    final lab = Oklab.fromRgb(rgb);
    var best = _refs.first;
    var bestD = lab.distance2(best.$2);
    for (final r in _refs.skip(1)) {
      final d = lab.distance2(r.$2);
      if (d < bestD) {
        best = r;
        bestD = d;
      }
    }
    return best.$1;
  }

  /// As maiores, em passos de 10 % (mínimo 10 %), a somar 100 %.
  static List<GarmentColor> _proportions(Map<ReferenceColor, int> counts) {
    final total = counts.values.fold(0, (s, v) => s + v);
    final ranked =
        counts.entries.where((e) => e.value / total >= minShare).toList()
          ..sort((a, b) {
            final c = b.value.compareTo(a.value);
            return c != 0 ? c : a.key.index.compareTo(b.key.index);
          });
    final chosen = ranked.take(maxColors).toList();
    if (chosen.isEmpty) return const [];
    final sum = chosen.fold(0, (s, e) => s + e.value);
    final tens = [
      for (final e in chosen) (e.value * 10 / sum).round().clamp(1, 10),
    ];
    // Acerta a maior para somar 10 décimos.
    tens[0] += 10 - tens.fold(0, (s, v) => s + v);
    return [
      for (final (i, e) in chosen.indexed)
        if (tens[i] > 0)
          GarmentColor.create(rgb: e.key.rgb, proportion: tens[i] / 10)!,
    ];
  }
}
