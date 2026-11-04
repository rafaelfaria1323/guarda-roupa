import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'garment_category.dart';

/// Embeddings dos textos de cada categoria (calculados uma vez com o
/// encoder de texto do FashionCLIP: tool/models/category_embeddings.py).
final class CategoryTexts {
  CategoryTexts(this.embeddings);

  final Map<GarmentCategory, Float32List> embeddings;

  /// `null` se o JSON não servir.
  static CategoryTexts? fromJson(Object? json) {
    if (json is! Map || json['categories'] is! Map) return null;
    final out = <GarmentCategory, Float32List>{};
    for (final MapEntry(:key, :value) in (json['categories'] as Map).entries) {
      final category = key is String ? GarmentCategory.fromId(key) : null;
      if (category == null || value is! List || value.any((v) => v is! num)) {
        return null;
      }
      out[category] = _normalized([
        for (final v in value) (v as num).toDouble(),
      ]);
    }
    if (out.isEmpty) return null;
    final dim = out.values.first.length;
    if (out.values.any((e) => e.length != dim)) return null;
    return CategoryTexts(out);
  }
}

/// Entrada e saída do encoder de imagem do Marqo FashionCLIP (ViT-B/16):
/// lado menor a 224, recorte central 224×224, normalização do CLIP. A
/// categoria é a do texto mais parecido (cosseno), sem limiar: é sempre
/// uma sugestão para o utilizador escolher.
abstract final class FashionClip {
  static const side = 224;
  static const _mean = [0.48145466, 0.4578275, 0.40821073];
  static const _std = [0.26862954, 0.26130258, 0.27577711];

  /// Tensor `[1, 3, 224, 224]` (NCHW). `null` se a imagem não se ler.
  static Float32List? input(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null || decoded.width == 0 || decoded.height == 0) {
      return null;
    }
    final scale = side / math.min(decoded.width, decoded.height);
    final w = math.max(side, (decoded.width * scale).round());
    final h = math.max(side, (decoded.height * scale).round());
    final resized = img.copyResize(
      decoded,
      width: w,
      height: h,
      interpolation: scale < 1
          ? img.Interpolation.average
          : img.Interpolation.cubic,
    );
    final left = (w - side) ~/ 2;
    final top = (h - side) ~/ 2;
    const plane = side * side;
    final out = Float32List(plane * 3);
    for (var y = 0; y < side; y++) {
      for (var x = 0; x < side; x++) {
        final p = resized.getPixel(left + x, top + y);
        final max = p.maxChannelValue;
        final i = y * side + x;
        out[i] = (p.r / max - _mean[0]) / _std[0];
        out[plane + i] = (p.g / max - _mean[1]) / _std[1];
        out[2 * plane + i] = (p.b / max - _mean[2]) / _std[2];
      }
    }
    return out;
  }

  /// As [top] categorias mais parecidas com a foto, da mais provável para a
  /// menos. `[]` se o embedding não tiver a dimensão dos textos.
  static List<GarmentCategory> rank(
    List<num> imageEmbedding,
    CategoryTexts texts, {
    int top = 3,
  }) {
    final dim = texts.embeddings.values.first.length;
    if (imageEmbedding.length != dim) return const [];
    final image = _normalized([for (final v in imageEmbedding) v.toDouble()]);
    final scored =
        [
          for (final MapEntry(key: c, value: t) in texts.embeddings.entries)
            (c, _dot(image, t)),
        ]..sort((a, b) {
          final d = b.$2.compareTo(a.$2);
          return d != 0 ? d : a.$1.index.compareTo(b.$1.index);
        });
    return [for (final (c, _) in scored.take(top)) c];
  }

  /// Com norma 1 (para comparar por produto interno).
  static Float32List normalize(List<num> v) =>
      _normalized([for (final x in v) x.toDouble()]);

  /// Cosseno entre dois embeddings já normalizados; `null` se as
  /// dimensões diferirem.
  static double? cosine(Float32List a, Float32List b) =>
      a.length == b.length ? _dot(a, b) : null;

  static double _dot(Float32List a, Float32List b) {
    var s = 0.0;
    for (var i = 0; i < a.length; i++) {
      s += a[i] * b[i];
    }
    return s;
  }
}

Float32List _normalized(List<double> v) {
  var n = 0.0;
  for (final x in v) {
    n += x * x;
  }
  n = math.sqrt(n);
  return Float32List.fromList([for (final x in v) n == 0 ? 0 : x / n]);
}
