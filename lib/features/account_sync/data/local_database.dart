import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:powersync/powersync.dart';

import '../../wardrobe/data/photo_files.dart';
import '../../weather/data/weather_repository.dart';
import 'local_schema.dart';

/// Abre a base local **da conta indicada** (ADR-008: uma base por conta;
/// nunca se reutiliza a base de outra conta).
Future<PowerSyncDatabase> openUserDatabase(String userId) async {
  final name = 'guarda_roupa_$userId.db';
  final path = kIsWeb
      ? name
      : '${(await getApplicationSupportDirectory()).path}/$name';
  final db = PowerSyncDatabase(schema: localSchema, path: path);
  await db.initialize();
  await prepareLocalTables(db);
  return db;
}

/// Tabelas locais fora do schema do PowerSync (bytes das fotos, previsão e
/// definições deste dispositivo).
Future<void> prepareLocalTables(PowerSyncDatabase db) async {
  await db.execute(PhotoFiles.createTable);
  for (final sql in WeatherTables.create) {
    await db.execute(sql);
  }
}
