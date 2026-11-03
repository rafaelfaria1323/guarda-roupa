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
/// - Escritas em `garments`: são só a visão otimista local; o servidor não
///   aceita escrita direta, por isso não se enviam.
/// - `attach_photo`: os ficheiros vão primeiro; o servidor só liga a foto se
///   existirem. Uma falha no envio deixa a operação na fila.
/// - `detach_photo`: depois de enviada, apagam-se os ficheiros (no Storage,
///   em melhor esforço, e neste dispositivo).
final class OperationUploadQueue {
  const OperationUploadQueue(this._uploader);

  final OperationUploader _uploader;

  Future<void> upload(PowerSyncDatabase db) async {
    while (true) {
      final transaction = await db.getNextCrudTransaction();
      if (transaction == null) return;

      final outcomes = <(CrudEntry, Map<String, Object?>)>[];
      for (final entry in transaction.crud) {
        if (entry.table != 'garment_operations' || entry.op != UpdateType.put) {
          continue;
        }
        final data = entry.opData ?? const {};
        final kind = data['kind'];
        final payload = jsonDecode(data['data'] as String? ?? '{}');
        if (kind == 'attach_photo') await _uploadFiles(db, payload);
        final result = await _uploader.apply({
          'op_id': entry.id,
          'garment_id': data['garment_id'],
          'kind': kind,
          'data': payload,
        });
        outcomes.add((entry, result));
      }

      final detached = [
        for (final (entry, _) in outcomes)
          if (entry.opData?['kind'] == 'detach_photo')
            if (jsonDecode(entry.opData?['data'] as String? ?? '{}') case {
              'photo_id': final String id,
            })
              id,
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
              entry.opData?['garment_id'],
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

  Future<void> _uploadFiles(PowerSyncDatabase db, Object? payload) async {
    if (payload case {'photo': {'id': final String photoId}}) {
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
