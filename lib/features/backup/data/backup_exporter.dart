import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:powersync/powersync.dart';

import '../../../core/domain/result.dart';
import '../../wardrobe/data/garment_row.dart';
import '../../wardrobe/data/photo_files.dart';
import '../../wardrobe/domain/garment_photo.dart';
import '../domain/backup.dart';
import 'backup_codec.dart';

/// Descarrega uma variante de uma foto que não está neste dispositivo;
/// `null` se não houver cloud.
typedef RemotePhoto = Future<Uint8List?> Function(
  GarmentPhoto photo,
  PhotoVariant variant,
);

/// Gera o ficheiro de backup a partir da base local.
final class BackupExporter {
  BackupExporter({required this._db, this._remote});

  final PowerSyncDatabase _db;
  final RemotePhoto? _remote;

  Future<Result<Uint8List, BackupProblem>> export({DateTime? now}) async {
    // 1. Snapshot consistente: peças, bytes locais e pendências na mesma
    //    transação de leitura.
    final (garments, local, pending) = await _db.readTransaction((tx) async {
      final rows = await tx.getAll(
        'SELECT * FROM garments WHERE deleted_at IS NULL '
        'ORDER BY created_at, id',
      );
      final garments = [for (final row in rows) ?GarmentRow.fromRow(row)];
      final local = <(String, PhotoVariant), Uint8List>{};
      for (final g in garments) {
        for (final photo in g.photos) {
          for (final variant in PhotoVariant.values) {
            if (await PhotoFiles.get(tx, photo.id, variant) case final b?) {
              local[(photo.id, variant)] = b;
            }
          }
        }
      }
      final pending = await tx.get(
        'SELECT count(*) AS n FROM ps_crud '
        r"WHERE json_extract(data, '$.type') = 'garment_operations'",
      );
      return (garments, local, pending['n']! as int);
    });

    // 2–3. Reunir as fotos que faltam e confirmar que nenhuma fica de fora.
    final files = <(String, PhotoVariant), Uint8List>{...local};
    var missing = 0;
    for (final g in garments) {
      for (final photo in g.photos) {
        for (final variant in PhotoVariant.values) {
          if (files.containsKey((photo.id, variant))) continue;
          final bytes = await _download(photo, variant);
          if (bytes == null) {
            missing++;
          } else {
            files[(photo.id, variant)] = bytes;
          }
        }
      }
    }
    if (missing > 0) return Err(MissingPhotos(missing));

    // 4. Manifest, hashes e ZIP, verificado com o mesmo leitor da
    //    recuperação antes de o entregar.
    final zip = BackupCodec.encode(
      garments: garments,
      photoFiles: files,
      exportedAt: now ?? DateTime.now(),
      pendingOperations: pending,
    );
    return switch (BackupCodec.decode(zip)) {
      Ok(value: BackupContents(:final summary))
          when summary.garments == garments.length =>
        Ok(zip),
      Ok() => const Err(CorruptBackup('verificação')),
      Err(:final failure) => Err(failure),
    };
  }

  Future<Uint8List?> _download(GarmentPhoto photo, PhotoVariant variant) async {
    final remote = _remote;
    if (remote == null) return null;
    try {
      final bytes = await remote(photo, variant);
      if (bytes == null) return null;
      if (variant == PhotoVariant.main &&
          sha256.convert(bytes).toString() != photo.sha256) {
        return null;
      }
      return bytes;
    } on Object {
      return null;
    }
  }
}

/// Nome sugerido: `guarda-roupa-AAAA-MM-DD-HHMM` (hora local).
String backupFileName(DateTime when) {
  String two(int v) => v.toString().padLeft(2, '0');
  final t = when.toLocal();
  return 'guarda-roupa-${t.year}-${two(t.month)}-${two(t.day)}-'
      '${two(t.hour)}${two(t.minute)}';
}
