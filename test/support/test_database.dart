import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:guarda_roupa/features/account_sync/data/local_schema.dart';
import 'package:powersync/powersync.dart';

/// Base PowerSync real (SQLite em ficheiro temporário) com o schema da app.
/// Fecha e apaga no fim do teste.
Future<PowerSyncDatabase> openTestDatabase() async {
  final dir = Directory.systemTemp.createTempSync('guarda_roupa_test_');
  final db = PowerSyncDatabase(schema: localSchema, path: '${dir.path}/t.db');
  await db.initialize();
  addTearDown(() async {
    await db.close();
    dir.deleteSync(recursive: true);
  });
  return db;
}

/// Operações pendentes na fila de upload, pela ordem em que foram feitas.
Future<List<Map<String, Object?>>> pendingOperations(
  PowerSyncDatabase db,
) async {
  final batch = await db.getCrudBatch(limit: 1000);
  return [
    for (final e in batch?.crud ?? const <CrudEntry>[])
      if (e.table == 'garment_operations') {'id': e.id, ...?e.opData},
  ];
}
