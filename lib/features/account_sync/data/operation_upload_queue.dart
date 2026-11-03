import 'dart:convert';

import 'dart:typed_data';

import 'package:powersync/powersync.dart';

import '../../wardrobe/data/photo_files.dart';
import '../../wardrobe/domain/garment_photo.dart';

/// Envia uma operação de domínio ao servidor e devolve a resposta JSON de
/// `apply_garment_operation`. Lança exceção em falhas de rede ou sessão
/// (a operação fica na fila e é repetida); rejeições de negócio chegam como
/// resposta normal.
abstract interface class OperationUploader {
  Future<Map<String, Object?>> apply(Map<String, Object?> operation);

  /// Envia uma operação de utilização (`apply_wear_operation`). Mesmas
  /// regras de erro que [apply].
  Future<Map<String, Object?>> applyWear(Map<String, Object?> operation);

  /// Envia uma operação de conjunto (`apply_outfit_operation`). Mesmas
  /// regras de erro que [apply].
  Future<Map<String, Object?>> applyOutfit(Map<String, Object?> operation);

  /// Envia uma operação de estilo (`apply_style_operation`). Mesmas regras
  /// de erro que [apply].
  Future<Map<String, Object?>> applyStyle(Map<String, Object?> operation);

  /// Envia um ficheiro de foto. Idempotente; lança em falha de rede.
  Future<void> uploadPhotoFile(
    String photoId,
    PhotoVariant variant,
    Uint8List bytes,
  );

  /// Apaga os ficheiros de uma foto desligada. Melhor esforço.
  Future<void> removePhotoFiles(String photoId);
}

/// Processa a fila de upload do PowerSync, uma transação local de cada vez
/// e pela ordem em que foram feitas.
///
/// - `garment_operations` (PUT): enviadas ao servidor. Resultados diferentes
///   de `applied` ficam em `sync_conflicts` para o utilizador ver.
/// - `wear_operations` (PUT): enviadas a `apply_wear_operation`, com as
///   mesmas regras; em `sync_conflicts`, `garment_id` guarda o id da
///   utilização.
/// - `outfit_operations` (PUT): enviadas a `apply_outfit_operation`; em
///   `sync_conflicts`, `garment_id` guarda o id do conjunto.
/// - `style_operations` (PUT): enviadas a `apply_style_operation`; em
///   `sync_conflicts`, `garment_id` guarda o id da inspiração.
/// - Escritas em `garments`: são só a visão otimista local; o servidor não
///   aceita escrita direta, por isso não se enviam.
/// - `attach_photo`: os ficheiros vão primeiro; o servidor só liga a foto se
///   existirem. Uma falha no envio deixa a operação na fila.
/// - `detach_photo` e `delete`: depois de enviadas, apagam-se os ficheiros
///   das fotos (no Storage, em melhor esforço, e neste dispositivo).
/// - Imagens das inspirações: o mesmo, com `set_inspiration_image` (envia
///   primeiro) e `remove_inspiration_image`/`delete_inspiration` (apagam
///   depois).
final class OperationUploadQueue {
  const OperationUploadQueue(this._uploader);

  final OperationUploader _uploader;

  Future<void> upload(PowerSyncDatabase db) async {
    while (true) {
      final transaction = await db.getNextCrudTransaction();
      if (transaction == null) return;

      final outcomes = <(CrudEntry, Map<String, Object?>)>[];
      for (final entry in transaction.crud) {
        if (entry.op != UpdateType.put) continue;
        final data = entry.opData ?? const {};
        final kind = data['kind'];
        final payload = jsonDecode(data['data'] as String? ?? '{}');
        switch (entry.table) {
          case 'garment_operations':
            if (kind == 'attach_photo') {
              await _uploadFiles(db, _photoId(payload, 'photo'));
            }
            outcomes.add((
              entry,
              await _uploader.apply({
                'op_id': entry.id,
                'garment_id': data['garment_id'],
                'kind': kind,
                'data': payload,
              }),
            ));
          case 'wear_operations':
            outcomes.add((
              entry,
              await _uploader.applyWear({
                'op_id': entry.id,
                'event_id': data['event_id'],
                'kind': kind,
                'data': payload,
              }),
            ));
          case 'outfit_operations':
            outcomes.add((
              entry,
              await _uploader.applyOutfit({
                'op_id': entry.id,
                'outfit_id': data['outfit_id'],
                'kind': kind,
                'data': payload,
              }),
            ));
          case 'style_operations':
            if (kind == 'set_inspiration_image') {
              await _uploadFiles(db, _photoId(payload, 'image'));
            }
            outcomes.add((
              entry,
              await _uploader.applyStyle({
                'op_id': entry.id,
                'entity_id': data['entity_id'],
                'kind': kind,
                'data': payload,
              }),
            ));
        }
      }

      final detached = [
        for (final (entry, _) in outcomes)
          ..._removedPhotos(
            entry.table,
            entry.opData?['kind'],
            jsonDecode(entry.opData?['data'] as String? ?? '{}'),
          ),
      ];
      for (final photoId in detached) {
        try {
          await _uploader.removePhotoFiles(photoId);
        } on Object {
          // Ficheiro órfão no Storage: ocupa espaço, mas não aparece.
        }
      }

      await db.writeTransaction((tx) async {
        for (final photoId in detached) {
          await PhotoFiles.delete(tx, photoId);
        }
        for (final (entry, result) in outcomes) {
          final outcome = result['result'];
          if (outcome == 'applied') continue;
          await tx.execute(
            'INSERT INTO sync_conflicts (id, op_id, garment_id, kind, result, '
            'reason, details, created_at) VALUES (uuid(), ?, ?, ?, ?, ?, ?, ?)',
            [
              entry.id,
              entry.opData?['garment_id'] ??
                  entry.opData?['event_id'] ??
                  entry.opData?['outfit_id'] ??
                  entry.opData?['entity_id'],
              entry.opData?['kind'],
              outcome is String ? outcome : 'rejected',
              result['reason'],
              result['conflicts'] == null
                  ? null
                  : jsonEncode(result['conflicts']),
              DateTime.now().toUtc().toIso8601String(),
            ],
          );
        }
      });
      await transaction.complete();
    }
  }

  static List<String> _removedPhotos(
    String table,
    Object? kind,
    Object? payload,
  ) => switch ((table, kind, payload)) {
    ('garment_operations', 'detach_photo', {'photo_id': final String id}) => [
      id,
    ],
    ('garment_operations', 'delete', {'photo_ids': final List<Object?> ids}) =>
      [...ids.whereType<String>()],
    (
      'style_operations',
      'remove_inspiration_image' || 'delete_inspiration',
      {'photo_id': final String id},
    ) =>
      [id],
    _ => const [],
  };

  /// Id da foto em `payload[key]` (`{photo: {id…}}` ou `{image: {id…}}`).
  static String? _photoId(Object? payload, String key) => switch (payload) {
    final Map<String, Object?> map => switch (map[key]) {
      {'id': final String id} => id,
      _ => null,
    },
    _ => null,
  };

  Future<void> _uploadFiles(PowerSyncDatabase db, String? photoId) async {
    if (photoId != null) {
      for (final variant in PhotoVariant.values) {
        final bytes = await PhotoFiles.get(db, photoId, variant);
        // Sem bytes locais o servidor rejeita (missing_file) e o utilizador
        // vê o problema; não se liga uma foto vazia.
        if (bytes != null) {
          await _uploader.uploadPhotoFile(photoId, variant, bytes);
        }
      }
    }
  }
}
