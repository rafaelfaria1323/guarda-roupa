import 'dart:typed_data';

import 'package:sqlite_async/sqlite_async.dart';

import '../../wardrobe/domain/garment.dart';
import '../../wardrobe/domain/garment_photo.dart';
import '../../wardrobe/domain/similar_garments.dart';
import '../../wardrobe/domain/wardrobe_repository.dart';
import '../data/photo_embeddings.dart';
import '../domain/image_embedder.dart';

/// Resultado de [SimilarGarmentsFinder.find]: as mais parecidas e quantas
/// peças com foto ficaram de fora (foto que não está neste dispositivo ou
/// que não se leu).
typedef SimilarGarmentsResult = ({List<(Garment, double)> items, int skipped});

/// Compara uma imagem com a capa de cada peça. Cada capa analisa-se uma vez
/// por dispositivo; o embedding fica em [PhotoEmbeddings].
final class SimilarGarmentsFinder {
  SimilarGarmentsFinder(this._embedder, this._db, this._repo);

  final ImageEmbedder _embedder;
  final SqliteConnection _db;
  final WardrobeRepository _repo;

  /// `null` se a imagem [query] não se conseguir analisar. Só considera
  /// peças com foto e não arquivadas.
  Future<SimilarGarmentsResult?> find(
    Uint8List query,
    List<Garment> garments, {
    void Function(int done, int total)? onProgress,
  }) async {
    final q = await _embedder.embed(query);
    if (q == null) return null;
    final withPhoto = [
      for (final g in garments)
        if (!g.isArchived && g.photos.isNotEmpty) g,
    ];
    final candidates = <(Garment, Float32List)>[];
    var skipped = 0;
    for (final (i, g) in withPhoto.indexed) {
      onProgress?.call(i, withPhoto.length);
      final e = await _embeddingOf(g.photos.first.id);
      if (e == null) {
        skipped++;
      } else {
        candidates.add((g, e));
      }
    }
    onProgress?.call(withPhoto.length, withPhoto.length);
    return (items: SimilarGarments.rank(q, candidates), skipped: skipped);
  }

  Future<Float32List?> _embeddingOf(String photoId) async {
    final model = _embedder.modelId;
    try {
      final cached = await PhotoEmbeddings.get(_db, photoId, model);
      if (cached != null) return cached;
      final bytes = await _repo.photoBytes(photoId, PhotoVariant.thumb);
      if (bytes == null) return null;
      final e = await _embedder.embed(bytes);
      if (e == null) return null;
      await _db.writeTransaction(
        (tx) => PhotoEmbeddings.put(tx, photoId, model, e),
      );
      return e;
    } on Object {
      return null; // fica de fora; tenta-se de novo na próxima vez
    }
  }
}
