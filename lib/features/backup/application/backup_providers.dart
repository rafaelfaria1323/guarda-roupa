import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../account_sync/application/providers.dart';
import '../../wardrobe/application/photo_providers.dart';
import '../../wardrobe/domain/garment_photo.dart';
import '../data/backup_exporter.dart';
import '../data/file_saver_backup_saver.dart';
import '../domain/backup_saver.dart';

final backupSaverProvider = Provider<BackupSaver>(
  (ref) => const FileSaverBackupSaver(),
);

/// `null` enquanto a base da conta não está aberta.
final backupExporterProvider = Provider<BackupExporter?>((ref) {
  final db = ref.watch(userDatabaseProvider).value;
  if (db == null) return null;
  final storage = ref.watch(photoStorageProvider);
  final userId = ref.watch(currentUserProvider).value?.id;
  return BackupExporter(
    db: db,
    remote: storage == null || userId == null
        ? null
        : (photo, variant) => storage.download(
            PhotoRules.storagePath(userId, photo.id, variant),
          ),
  );
});
