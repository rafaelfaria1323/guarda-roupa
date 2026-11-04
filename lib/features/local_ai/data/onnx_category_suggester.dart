import 'dart:convert';

import 'package:flutter/services.dart';

import '../../wardrobe/domain/category_suggestion.dart';
import '../../wardrobe/domain/garment_category.dart';
import '../domain/category_suggester.dart';
import '../domain/image_embedder.dart';

/// Categorias pelo embedding da foto, contra os textos das categorias em
/// [textsAsset] (calculados com o mesmo FashionCLIP).
final class EmbeddingCategorySuggester implements CategorySuggester {
  EmbeddingCategorySuggester(this._embedder, {AssetBundle? bundle})
    : _bundle = bundle ?? rootBundle;

  static const textsAsset = 'assets/models/fashionclip_categories.json';

  final ImageEmbedder _embedder;
  final AssetBundle _bundle;
  CategoryTexts? _texts;

  @override
  Future<List<GarmentCategory>?> suggest(Uint8List bytes) async {
    final texts = _texts ??= CategoryTexts.fromJson(
      jsonDecode(await _bundle.loadString(textsAsset)),
    );
    if (texts == null) return null;
    final embedding = await _embedder.embed(bytes);
    if (embedding == null) return null;
    final ranked = FashionClip.rank(embedding, texts);
    return ranked.isEmpty ? null : ranked;
  }

  // O embedder é partilhado; fecha-o quem o criou.
  @override
  Future<void> close() async {}
}
