import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart';

import '../domain/backup_saver.dart';

/// No Android o diálogo do sistema (SAF) grava fora da pasta privada da app,
/// que não serve de backup; na Web inicia uma transferência.
final class FileSaverBackupSaver implements BackupSaver {
  const FileSaverBackupSaver();

  @override
  Future<SaveOutcome> save(String name, Uint8List zip) async {
    final path = await FileSaver.instance.saveAs(
      name: name,
      bytes: zip,
      fileExtension: 'zip',
      mimeType: MimeType.zip,
    );
    if (kIsWeb) return SaveOutcome.downloadStarted;
    return path == null || path.isEmpty
        ? SaveOutcome.cancelled
        : SaveOutcome.saved;
  }
}
