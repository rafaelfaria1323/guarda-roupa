import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';

import '../../import/domain/product_photo.dart';
import '../../wardrobe/domain/category_suggestion.dart';
import '../domain/image_embedder.dart';

/// Os dois textos ("pessoa a vestir" e "peça sozinha") calculados com o
/// mesmo FashionCLIP (tool/models/photo_kind_embeddings.py).
final class PhotoKindTexts {
  PhotoKindTexts({
    required this.worn,
    required this.alone,
    required this.threshold,
  });

  final Float32List worn;
  final Float32List alone;
  final double threshold;

  /// `null` se o JSON não servir.
  static PhotoKindTexts? fromJson(Object? json) {
    if (json is! Map) return null;
    Float32List? vector(Object? v) =>
        v is List && v.isNotEmpty && v.every((x) => x is num)
        ? FashionClip.normalize([for (final x in v) x as num])
        : null;
    final worn = vector(json['worn']);
    final alone = vector(json['alone']);
    final threshold = json['threshold'];
    if (worn == null ||
        alone == null ||
        worn.length != alone.length ||
        threshold is! num) {
      return null;
    }
    return PhotoKindTexts(
      worn: worn,
      alone: alone,
      threshold: threshold.toDouble(),
    );
  }

  /// Cosseno com "sozinha" menos cosseno com "vestida"; `null` se a
  /// dimensão não bater.
  double? score(Float32List image) {
    final a = FashionClip.cosine(image, alone);
    final w = FashionClip.cosine(image, worn);
    return a == null || w == null ? null : a - w;
  }
}

/// [ProductPhotoScorer] com o FashionCLIP deste dispositivo.
final class EmbeddingPhotoScorer implements ProductPhotoScorer {
  EmbeddingPhotoScorer(this._embedder, {AssetBundle? bundle})
    : _bundle = bundle ?? rootBundle;

  static const textsAsset = 'assets/models/fashionclip_photo_kind.json';

  final ImageEmbedder _embedder;
  final AssetBundle _bundle;
  PhotoKindTexts? _texts;

  Future<PhotoKindTexts?> _load() async => _texts ??= PhotoKindTexts.fromJson(
    jsonDecode(await _bundle.loadString(textsAsset)),
  );

  @override
  double get threshold => _texts?.threshold ?? 0.02;

  @override
  Future<double?> score(Uint8List bytes) async {
    final texts = await _load();
    if (texts == null) return null;
    final embedding = await _embedder.embed(bytes);
    return embedding == null ? null : texts.score(embedding);
  }
}
