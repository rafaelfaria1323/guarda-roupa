import 'dart:typed_data';

import '../../wardrobe/domain/category_suggestion.dart';
import '../domain/image_embedder.dart';
import '../domain/local_model.dart';
import 'onnx_model.dart';

/// Encoder de imagem do FashionCLIP com o ONNX Runtime.
final class OnnxImageEmbedder implements ImageEmbedder {
  OnnxImageEmbedder(ModelStore store, LocalModel model)
    : modelId = model.id,
      _model = OnnxModel(store, model);

  @override
  final String modelId;
  final OnnxModel _model;

  @override
  Future<Float32List?> embed(Uint8List bytes) async {
    final input = FashionClip.input(bytes);
    if (input == null) return null;
    final out = await _model.run(input, const [
      1,
      3,
      FashionClip.side,
      FashionClip.side,
    ]);
    return out == null ? null : FashionClip.normalize(out);
  }

  @override
  Future<void> close() => _model.close();
}
