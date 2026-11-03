import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

import '../domain/backup.dart';
import '../domain/backup_picker.dart';

final class FileSelectorBackupPicker implements BackupPicker {
  const FileSelectorBackupPicker();

  static const _zip = XTypeGroup(
    label: 'ZIP',
    extensions: ['zip'],
    mimeTypes: ['application/zip', 'application/x-zip-compressed'],
    uniformTypeIdentifiers: ['public.zip-archive'],
  );

  @override
  Future<Uint8List?> pick() async {
    final file = await openFile(acceptedTypeGroups: const [_zip]);
    if (file == null) return null;
    // Antes de ler tudo para memória.
    if (await file.length() > BackupFormat.maxTotalBytes) {
      throw const FormatException('Ficheiro demasiado grande');
    }
    return file.readAsBytes();
  }
}
