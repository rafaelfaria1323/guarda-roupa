import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:powersync/powersync.dart';
import 'package:sqlite_async/sqlite_async.dart';

import '../../../core/domain/result.dart';
import '../../care/data/powersync_care_repository.dart';
import '../../care/domain/care_policies.dart';
import '../../inspirations/data/powersync_inspiration_repository.dart';
import '../../inspirations/data/powersync_preference_repository.dart';
import '../../inspirations/domain/style_preference.dart';
import '../../outfits/data/powersync_outfit_repository.dart';
import '../../outfits/domain/outfit.dart';
import '../../wardrobe/data/garment_row.dart';
import '../../wardrobe/data/photo_files.dart';
import '../../wardrobe/domain/garment.dart';
import '../../wardrobe/domain/garment_category.dart';
import '../../wardrobe/domain/garment_photo.dart';
import '../../wear/data/powersync_wear_repository.dart';
import '../../wear/domain/wear_event.dart';
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
    // 1. Snapshot consistente: peças, histórico, bytes locais e pendências
    //    na mesma transação de leitura.
    final (garments, history, local, pending) = await _db.readTransaction((
      tx,
    ) async {
      final rows = await tx.getAll(
        'SELECT * FROM garments WHERE deleted_at IS NULL '
        'ORDER BY created_at, id',
      );
      final garments = [for (final row in rows) ?GarmentRow.fromRow(row)];
      final history = await _history(tx, {
        for (final g in garments) g.id.value,
      });
      final local = <(String, PhotoVariant), Uint8List>{};
      for (final photo in _photos(garments, history)) {
        for (final variant in PhotoVariant.values) {
          if (await PhotoFiles.get(tx, photo.id, variant) case final b?) {
            local[(photo.id, variant)] = b;
          }
        }
      }
      final pending = await tx.get(
        'SELECT count(*) AS n FROM ps_crud '
        r"WHERE json_extract(data, '$.type') IN "
        "('garment_operations', 'wear_operations', 'outfit_operations', 'style_operations', 'plan_operations')",
      );
      return (garments, history, local, pending['n']! as int);
    });

    // 2–3. Reunir as fotos que faltam e confirmar que nenhuma fica de fora.
    final files = <(String, PhotoVariant), Uint8List>{...local};
    var missing = 0;
    for (final photo in _photos(garments, history)) {
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
    if (missing > 0) return Err(MissingPhotos(missing));

    // 4. Manifest, hashes e ZIP, verificado com o mesmo leitor da
    //    recuperação antes de o entregar.
    final zip = BackupCodec.encode(
      garments: garments,
      photoFiles: files,
      exportedAt: now ?? DateTime.now(),
      pendingOperations: pending,
      history: history,
    );
    return switch (BackupCodec.decode(zip)) {
      Ok(value: BackupContents(:final summary))
          when summary.garments == garments.length =>
        Ok(zip),
      Ok() => const Err(CorruptBackup('verificação')),
      Err(:final failure) => Err(failure),
    };
  }

  /// Fotografias das peças e imagens das inspirações (desde a v5).
  static Iterable<GarmentPhoto> _photos(
    List<Garment> garments,
    BackupHistory history,
  ) => [
    for (final g in garments) ...g.photos,
    for (final i in history.inspirations) ?i.image,
  ];

  /// Só o que está ativo e refere peças que vão no backup: uma utilização
  /// com peças entretanto eliminadas fica só com as restantes.
  static Future<BackupHistory> _history(
    SqliteReadContext tx,
    Set<String> kept,
  ) async {
    final wears = <WearEvent>[];
    for (final row in await tx.getAll(
      'SELECT * FROM wear_events WHERE voided_at IS NULL '
      'ORDER BY worn_on, created_at, id',
    )) {
      final w = PowerSyncWearRepository.fromRow(row);
      if (w == null) continue;
      final pieces = w.garmentIds.where((g) => kept.contains(g.value)).toSet();
      if (pieces.isEmpty) continue;
      wears.add(
        WearEvent(
          id: w.id,
          wornOn: w.wornOn,
          garmentIds: pieces.toList(),
          createdAt: w.createdAt,
        ),
      );
    }
    final cleanings = [
      for (final row in await tx.getAll(
        'SELECT * FROM cleaning_events WHERE voided_at IS NULL '
        'ORDER BY cleaned_on, created_at, id',
      ))
        if (PowerSyncCareRepository.cleaningFromRow(row) case final c?
            when kept.contains(c.garmentId.value))
          c,
    ];
    final policies = <String, BackupPolicy>{};
    for (final row in await tx.getAll(
      'SELECT * FROM care_policies ORDER BY updated_at, id',
    )) {
      final scope = PolicyScope.fromId(row['scope'] as String?);
      final target = row['target'] as String?;
      final laundry = row['laundry_after'] as int?;
      final rotation = row['rotation_days'] as int?;
      if (scope == null || target == null) continue;
      if (laundry == null && rotation == null) continue;
      final valid = switch (scope) {
        PolicyScope.category => GarmentCategory.fromId(target) != null,
        PolicyScope.garment => kept.contains(target),
      };
      if (!valid) continue;
      // Repetidas (não deviam existir): a mais recente ganha.
      policies['${scope.id}:$target'] = BackupPolicy(
        scope: scope,
        target: target,
        laundryAfter: laundry,
        rotationDays: rotation,
      );
    }
    // Conjuntos ativos, sem as peças eliminadas; um conjunto que fique sem
    // peças fica de fora.
    final outfits = <Outfit>[];
    for (final row in await tx.getAll(
      'SELECT * FROM outfits WHERE deleted_at IS NULL '
      'ORDER BY created_at, id',
    )) {
      final o = PowerSyncOutfitRepository.fromRow(row);
      if (o == null) continue;
      final items = [
        for (final i in o.items)
          if (kept.contains(i.garmentId.value)) i,
      ];
      if (items.isEmpty) continue;
      outfits.add(
        Outfit(
          id: o.id,
          name: o.name,
          occasions: o.occasions,
          items: items,
          createdAt: o.createdAt,
          updatedAt: o.updatedAt,
        ),
      );
    }
    // Inspirações e preferências ativas. Uma preferência cuja inspiração já
    // foi eliminada vai sem origem.
    final inspirations = [
      for (final row in await tx.getAll(
        'SELECT * FROM inspirations WHERE deleted_at IS NULL '
        'ORDER BY created_at, id',
      ))
        ?PowerSyncInspirationRepository.fromRow(row),
    ];
    final exported = {for (final i in inspirations) i.id};
    final preferences = [
      for (final row in await tx.getAll(
        'SELECT * FROM style_preferences WHERE deleted_at IS NULL '
        'ORDER BY created_at, id',
      ))
        if (PowerSyncPreferenceRepository.fromRow(row) case final p?)
          exported.contains(p.inspirationId)
              ? p
              : StylePreference(
                  id: p.id,
                  subject: p.subject,
                  value: p.value,
                  stance: p.stance,
                  occasions: p.occasions,
                  createdAt: p.createdAt,
                  updatedAt: p.updatedAt,
                ),
    ];
    return BackupHistory(
      wears: wears,
      cleanings: cleanings,
      policies: policies.values.toList(),
      outfits: outfits,
      inspirations: inspirations,
      preferences: preferences,
    );
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
