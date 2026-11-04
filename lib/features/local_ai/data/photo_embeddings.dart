import 'dart:typed_data';

import 'package:sqlite_async/sqlite_async.dart';

/// Embeddings das fotos já analisadas neste dispositivo, por foto e modelo
/// (fora do schema sincronizado; recalculam-se se faltarem). As fotos são
/// imutáveis: o id chega para saber que o embedding vale.
abstract final class PhotoEmbeddings {
  static const createTable =
      'CREATE TABLE IF NOT EXISTS photo_embeddings ('
      'photo_id TEXT NOT NULL, model TEXT NOT NULL, data BLOB NOT NULL, '
      'PRIMARY KEY (photo_id, model))';

  static Future<Float32List?> get(
    SqliteReadContext ctx,
    String photoId,
    String model,
  ) async {
    final row = await ctx.getOptional(
      'SELECT data FROM photo_embeddings WHERE photo_id = ? AND model = ?',
      [photoId, model],
    );
    final data = row?['data'];
    if (data is! Uint8List || data.lengthInBytes % 4 != 0) return null;
    // Cópia: o blob pode não estar alinhado a 4 bytes.
    return Uint8List.fromList(data).buffer.asFloat32List();
  }

  static Future<void> put(
    SqliteWriteContext tx,
    String photoId,
    String model,
    Float32List embedding,
  ) => tx.execute(
    'INSERT OR REPLACE INTO photo_embeddings (photo_id, model, data) '
    'VALUES (?, ?, ?)',
    [photoId, model, Uint8List.sublistView(embedding)],
  );

  static Future<void> clear(SqliteWriteContext tx) =>
      tx.execute('DELETE FROM photo_embeddings');
}
