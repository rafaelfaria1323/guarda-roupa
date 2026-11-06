import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'foreground_mask.dart';
import 'garment_color.dart';
import 'oklab.dart';
import 'reference_color.dart';

/// Cores sugeridas a partir de uma foto, sem modelo (baseline da IA local,
/// docs/features/ia-local.md). Cada píxel vai para a cor de referência mais
/// próxima em OKLab. O fundo tira-se com a máscara do recorte (IA local,
/// se o modelo estiver neste dispositivo) ou, sem ela, estima-se pela borda
/// da foto.
///
/// O resultado é sempre uma sugestão (`confirmed: false`): sombras, reflexos
/// e fundos parecidos com a peça enganam.
abstract final class PhotoColors {
  /// Lado máximo da imagem reduzida que se analisa.
  static const sampleSide = 64;

  /// A borda é fundo se uma só cor ocupar pelo menos isto dela.
  static const backgroundShare = 0.6;

  /// Distância OKLab até à cor típica da borda que ainda conta como fundo.
  /// Apanha fundos de estúdio com gradiente (bege a creme), que caem em
  /// duas cores de referência e nenhuma chega a [backgroundShare].
  static const backgroundDistance = 0.06;

  /// Sem o fundo, tem de sobrar isto da imagem; senão a peça é da cor do
  /// fundo (ou ocupa a foto toda) e o fundo não se tira.
  static const minForeground = 0.15;

  /// Uma cor entra se ocupar pelo menos isto do que sobra.
  static const minShare = 0.1;
  static const maxColors = 3;

  /// Uma máscara que marque menos do que isto como peça (ou quase tudo) não
  /// recortou nada de útil: usa-se a borda.
  static const minMaskShare = 0.02;
  static const maxMaskShare = 0.98;

  static final _refs = [
    for (final c in ReferenceColor.values) (c, Oklab.fromRgb(c.rgb)),
  ];

  /// `[]` se a imagem não se ler. Com [mask], só conta o que for peça.
  static List<GarmentColor> suggest(Uint8List bytes, {ForegroundMask? mask}) {
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
    final useMask =
        mask != null &&
        mask.share >= minMaskShare &&
        mask.share <= maxMaskShare;
    final grid = List<ReferenceColor?>.filled(w * h, null);
    final labs = List<Oklab?>.filled(w * h, null);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final p = image.getPixel(x, y);
        if (p.a < p.maxChannelValue / 2) continue; // transparente
        if (useMask && !mask.isForeground((x + 0.5) / w, (y + 0.5) / h)) {
          continue;
        }
        final rgb = (p.r.toInt() << 16) | (p.g.toInt() << 8) | p.b.toInt();
        final lab = Oklab.fromRgb(rgb);
        labs[y * w + x] = lab;
        grid[y * w + x] = _nearest(lab);
      }
    }

    // Fundo: a cor que domina a moldura exterior (1/10 de cada lado).
    final border = <ReferenceColor, int>{};
    final borderLabs = <Oklab>[];
    final bx = (w / 10).ceil();
    final by = (h / 10).ceil();
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        if (x >= bx && x < w - bx && y >= by && y < h - by) continue;
        final c = grid[y * w + x];
        if (c == null) continue;
        border[c] = (border[c] ?? 0) + 1;
        borderLabs.add(labs[y * w + x]!);
      }
    }
    final borderTotal = borderLabs.length;

    // Fundo por cor de referência (fundos lisos) ou pela distância à cor
    // típica da borda (fundos com gradiente).
    bool Function(int i)? isBackground;
    if (borderTotal > 0) {
      final top = border.entries.reduce((a, b) => b.value > a.value ? b : a);
      final typical = _median(borderLabs);
      const d2 = backgroundDistance * backgroundDistance;
      final near = borderLabs.where((l) => l.distance2(typical) <= d2).length;
      if (near / borderTotal >= backgroundShare) {
        isBackground = (i) =>
            grid[i] == top.key || labs[i]!.distance2(typical) <= d2;
      } else if (top.value / borderTotal >= backgroundShare) {
        isBackground = (i) => grid[i] == top.key;
      }
    }

    Map<ReferenceColor, int> count({bool Function(int i)? without}) {
      final out = <ReferenceColor, int>{};
      for (var i = 0; i < grid.length; i++) {
        final c = grid[i];
        if (c == null || (without != null && without(i))) continue;
        out[c] = (out[c] ?? 0) + 1;
      }
      return out;
    }

    final all = count();
    final total = all.values.fold(0, (s, v) => s + v);
    if (total == 0) return const [];
    var counts = all;
    if (isBackground != null && !useMask) {
      final rest = count(without: isBackground);
      final kept = rest.values.fold(0, (s, v) => s + v);
      if (kept / total >= minForeground) counts = rest;
    }
    return _proportions(counts);
  }

  /// Mediana por canal: a cor típica, sem ser puxada pela peça na borda.
  static Oklab _median(List<Oklab> labs) {
    double mid(List<double> v) => (v..sort())[v.length ~/ 2];
    return Oklab(
      mid([for (final l in labs) l.l]),
      mid([for (final l in labs) l.a]),
      mid([for (final l in labs) l.b]),
    );
  }

  static ReferenceColor _nearest(Oklab lab) {
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
