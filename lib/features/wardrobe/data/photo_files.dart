import 'dart:typed_data';

import 'package:sqlite_async/sqlite_async.dart';

import '../domain/garment_photo.dart';

/// Bytes das fotografias neste dispositivo, numa tabela SQLite própria
/// (fora do schema sincronizado). Na Web fica no mesmo armazenamento
/// persistente da base; um blob URL seria temporário.
///
/// Guarda as fotos tiradas aqui (até o servidor as aceitar e enquanto a peça
/// as tiver) e as descarregadas de outro dispositivo (cache).
abstract final class PhotoFiles {
  static const createTable =
      'CREATE TABLE IF NOT EXISTS photo_files ('
      'photo_id TEXT NOT NULL, variant TEXT NOT NULL, data BLOB NOT NULL, '
      'PRIMARY KEY (photo_id, variant))';

  static Future<void> put(
    SqliteWriteContext tx,
    String photoId,
    PhotoVariant variant,
    Uint8List bytes,
  ) => tx.execute(
    'INSERT OR REPLACE INTO photo_files (photo_id, variant, data) '
    'VALUES (?, ?, ?)',
    [photoId, variant.id, bytes],
  );

  static Future<Uint8List?> get(
    SqliteReadContext ctx,
    String photoId,
    PhotoVariant variant,
  ) async {
    final row = await ctx.getOptional(
      'SELECT data FROM photo_files WHERE photo_id = ? AND variant = ?',
      [photoId, variant.id],
    );
    final data = row?['data'];
    return data is Uint8List ? data : null;
  }

  static Future<void> delete(SqliteWriteContext tx, String photoId) =>
      tx.execute('DELETE FROM photo_files WHERE photo_id = ?', [photoId]);

  static Future<void> clear(SqliteWriteContext tx) =>
      tx.execute('DELETE FROM photo_files');
}
