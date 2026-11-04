import 'dart:convert';

import 'package:flutter/services.dart';

import '../../wardrobe/domain/category_suggestion.dart';
import '../../wardrobe/domain/garment_category.dart';
import '../domain/category_suggester.dart';
import '../domain/local_model.dart';
import 'onnx_model.dart';

/// FashionCLIP (encoder de imagem) com o ONNX Runtime, contra os textos das
/// categorias em [textsAsset].
final class OnnxCategorySuggester implements CategorySuggester {
  OnnxCategorySuggester(
    ModelStore store,
    LocalModel model, {
    AssetBundle? bundle,
  }) : _model = OnnxModel(store, model),
       _bundle = bundle ?? rootBundle;

  static const textsAsset = 'assets/models/fashionclip_categories.json';

  final OnnxModel _model;
  final AssetBundle _bundle;
  CategoryTexts? _texts;

  @override
  Future<List<GarmentCategory>?> suggest(Uint8List bytes) async {
    final texts = _texts ??= CategoryTexts.fromJson(
      jsonDecode(await _bundle.loadString(textsAsset)),
    );
    if (texts == null) return null;
    final input = FashionClip.input(bytes);
    if (input == null) return null;
    final out = await _model.run(input, const [
      1,
      3,
      FashionClip.side,
      FashionClip.side,
    ]);
    if (out == null) return null;
    final ranked = FashionClip.rank(out, texts);
    return ranked.isEmpty ? null : ranked;
  }

  @override
  Future<void> close() => _model.close();
}
