import 'dart:convert';

import 'package:sqlite_async/sqlite_async.dart';

import '../domain/comfort.dart';

/// Limites de conforto deste dispositivo (`local_settings`), como a
/// localização da previsão: são uma calibração pessoal, sem sincronizar.
final class ComfortStore {
  ComfortStore(this._db);

  final SqliteConnection _db;
  static const _key = 'comfort_thresholds';

  Future<ComfortThresholds> get() async {
    final row = await _db.getOptional(
      'SELECT value FROM local_settings WHERE key = ?',
      [_key],
    );
    final value = row?['value'];
    if (value is! String) return const ComfortThresholds();
    try {
      return ComfortThresholds.fromJson(jsonDecode(value)) ??
          const ComfortThresholds();
    } on FormatException {
      return const ComfortThresholds();
    }
  }

  Future<void> set(ComfortThresholds value) => _db.execute(
    'INSERT OR REPLACE INTO local_settings (key, value) VALUES (?, ?)',
    [_key, jsonEncode(value.toJson())],
  );
}
