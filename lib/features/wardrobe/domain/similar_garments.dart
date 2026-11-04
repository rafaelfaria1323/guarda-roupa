import 'dart:typed_data';

import 'category_suggestion.dart';
import 'garment.dart';

/// Peças parecidas com uma imagem (ex.: uma inspiração), por semelhança
/// visual do FashionCLIP. É só uma ordem para olhar: não diz que a peça
/// "serve" nem altera nada (docs/features/ia-local.md, tarefa 4).
abstract final class SimilarGarments {
  static const top = 5;

  /// As [top] peças mais parecidas, da mais para a menos; ignora embeddings
  /// de outra dimensão. Empates pela ordem recebida.
  static List<(Garment, double)> rank(
    Float32List query,
    List<(Garment, Float32List)> candidates, {
    int top = top,
  }) {
    final scored =
        <(int, Garment, double)>[
          for (final (i, (g, e)) in candidates.indexed)
            if (FashionClip.cosine(query, e) case final s?) (i, g, s),
        ]..sort((a, b) {
          final d = b.$3.compareTo(a.$3);
          return d != 0 ? d : a.$1.compareTo(b.$1);
        });
    return [for (final (_, g, s) in scored.take(top)) (g, s)];
  }
}
