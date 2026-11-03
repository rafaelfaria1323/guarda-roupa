import 'dart:convert';

import 'package:powersync/powersync.dart';

/// Envia uma operação de domínio ao servidor e devolve a resposta JSON de
/// `apply_garment_operation`. Lança exceção em falhas de rede ou sessão
/// (a operação fica na fila e é repetida); rejeições de negócio chegam como
/// resposta normal.
abstract interface class OperationUploader {
  Future<Map<String, Object?>> apply(Map<String, Object?> operation);
}

/// Processa a fila de upload do PowerSync, uma transação local de cada vez
/// e pela ordem em que foram feitas.
///
/// - `garment_operations` (PUT): enviadas ao servidor. Resultados diferentes
///   de `applied` ficam em `sync_conflicts` para o utilizador ver.
/// - Escritas em `garments`: são só a visão otimista local; o servidor não
///   aceita escrita direta, por isso não se enviam.
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
        final result = await _uploader.apply({
          'op_id': entry.id,
          'garment_id': data['garment_id'],
          'kind': data['kind'],
          'data': jsonDecode(data['data'] as String? ?? '{}'),
        });
        outcomes.add((entry, result));
      }

      await db.writeTransaction((tx) async {
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
}
