import 'dart:typed_data';

/// Embedding de uma foto (FashionCLIP), com norma 1; `null` se não
/// conseguir. Serve a categoria e as peças parecidas.
abstract interface class ImageEmbedder {
  /// Identifica o modelo: embeddings de modelos diferentes não se comparam.
  String get modelId;

  Future<Float32List?> embed(Uint8List bytes);

  Future<void> close();
}
