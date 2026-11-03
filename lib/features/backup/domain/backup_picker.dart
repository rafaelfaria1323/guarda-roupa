import 'dart:typed_data';

/// Escolhe um ficheiro de backup; `null` = cancelado.
abstract interface class BackupPicker {
  Future<Uint8List?> pick();
}
