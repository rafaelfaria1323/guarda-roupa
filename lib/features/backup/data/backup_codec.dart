import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

import '../../../core/domain/result.dart';
import '../../care/domain/care_policies.dart';
import '../../care/domain/cleaning_event.dart';
import '../../wardrobe/data/garment_row.dart';
import '../../wardrobe/domain/garment.dart';
import '../../wardrobe/domain/garment_category.dart';
import '../../wardrobe/domain/garment_photo.dart';
import '../../wear/domain/calendar_day.dart';
import '../../wear/domain/wear_event.dart';
import '../domain/backup.dart';

/// Conversão entre o conteúdo de um backup e o ficheiro ZIP.
///
/// Tudo em memória: com o limite de 5 fotos por peça (~0,5 MB cada), um
/// guarda-roupa de algumas centenas de peças fica bem abaixo dos limites de
/// memória dos telemóveis atuais. Ver custos-e-limitacoes.md.
abstract final class BackupCodec {
  /// JSON de uma peça, com as colunas do servidor (listas como listas).
  static Map<String, Object?> garmentJson(Garment g) => {
    'id': g.id.value,
    'category': g.category.id,
    'name': g.name,
    'brand': g.brand,
    'notes': g.notes,
    'colors': GarmentRow.colorsJson(g.colors),
    'photos': GarmentRow.photosJson(g.photos),
    'availability': g.availability.id,
    'archived_at': GarmentRow.iso(g.archivedAt),
    'created_at': GarmentRow.iso(g.createdAt),
    'updated_at': GarmentRow.iso(g.updatedAt),
    ...g.attributes.toColumns(),
  };

  /// Inverso de [garmentJson]; `null` se a peça não for válida.
  static Garment? garmentFromJson(Object? json) {
    if (json is! Map<String, Object?> || json['id'] is! String) return null;
    if (!_safeId.hasMatch(json['id']! as String)) return null;
    return GarmentRow.fromRow({
      ...json,
      for (final key in const ['colors', 'photos', 'occasions'])
        key: json[key] == null ? null : jsonEncode(json[key]),
    });
  }

  /// `data/history.json`. Sem `plan_entry_id`: o plano não vai no backup.
  static Map<String, Object?> historyJson(BackupHistory h) => {
    'wear_events': [
      for (final w in h.wears)
        {
          'id': w.id,
          'worn_on': w.wornOn.iso,
          'garment_ids': [for (final g in w.garmentIds) g.value],
          'created_at': GarmentRow.iso(w.createdAt),
        },
    ],
    'cleaning_events': [
      for (final c in h.cleanings)
        {
          'id': c.id,
          'garment_id': c.garmentId.value,
          'cleaned_on': c.cleanedOn.iso,
          'created_at': GarmentRow.iso(c.createdAt),
        },
    ],
    'care_policies': [
      for (final p in h.policies)
        {
          'scope': p.scope.id,
          'target': p.target,
          'laundry_after': p.laundryAfter,
          'rotation_days': p.rotationDays,
        },
    ],
  };

  /// Inverso de [historyJson]; `null` se algo for inválido ou referir uma
  /// peça que não está no backup.
  static BackupHistory? historyFromJson(Object? json, Set<String> garments) {
    if (json case {
      'wear_events': final List<Object?> rawWears,
      'cleaning_events': final List<Object?> rawCleanings,
      'care_policies': final List<Object?> rawPolicies,
    }) {
      final ids = <String>{};
      bool fresh(Object? id) =>
          id is String && _safeId.hasMatch(id) && ids.add(id);

      final wears = <WearEvent>[];
      for (final raw in rawWears) {
        if (raw
            case {
              'id': final Object? id,
              'worn_on': final String wornOn,
              'garment_ids': final List<Object?> list,
              'created_at': final String createdAt,
            }
            when fresh(id)) {
          final day = CalendarDay.tryParse(wornOn);
          final created = DateTime.tryParse(createdAt);
          final pieces = list.whereType<String>().toSet();
          if (day == null ||
              created == null ||
              pieces.isEmpty ||
              pieces.length != list.length ||
              pieces.length > WearRules.maxGarments ||
              !garments.containsAll(pieces)) {
            return null;
          }
          wears.add(
            WearEvent(
              id: id! as String,
              wornOn: day,
              garmentIds: [for (final g in pieces) GarmentId(g)],
              createdAt: created.toUtc(),
            ),
          );
        } else {
          return null;
        }
      }

      final cleanings = <CleaningEvent>[];
      for (final raw in rawCleanings) {
        if (raw
            case {
              'id': final Object? id,
              'garment_id': final String garment,
              'cleaned_on': final String cleanedOn,
              'created_at': final String createdAt,
            }
            when fresh(id) && garments.contains(garment)) {
          final day = CalendarDay.tryParse(cleanedOn);
          final created = DateTime.tryParse(createdAt);
          if (day == null || created == null) return null;
          cleanings.add(
            CleaningEvent(
              id: id! as String,
              garmentId: GarmentId(garment),
              cleanedOn: day,
              createdAt: created.toUtc(),
            ),
          );
        } else {
          return null;
        }
      }

      final policies = <BackupPolicy>[];
      final targets = <String>{};
      bool inRange(Object? v, int max) =>
          v == null || v is int && v >= 0 && v <= max;
      for (final raw in rawPolicies) {
        if (raw case {
          'scope': final String scopeId,
          'target': final String target,
          'laundry_after': final Object? laundry,
          'rotation_days': final Object? rotation,
        }) {
          final scope = PolicyScope.fromId(scopeId);
          final valid = switch (scope) {
            PolicyScope.category => GarmentCategory.fromId(target) != null,
            PolicyScope.garment => garments.contains(target),
            null => false,
          };
          if (!valid ||
              !targets.add('$scopeId:$target') ||
              !inRange(laundry, CareLimits.maxLaundryAfter) ||
              !inRange(rotation, CareLimits.maxRotationDays) ||
              (laundry == null && rotation == null)) {
            return null;
          }
          policies.add(
            BackupPolicy(
              scope: scope!,
              target: target,
              laundryAfter: laundry as int?,
              rotationDays: rotation as int?,
            ),
          );
        } else {
          return null;
        }
      }
      return BackupHistory(
        wears: List.unmodifiable(wears),
        cleanings: List.unmodifiable(cleanings),
        policies: List.unmodifiable(policies),
      );
    }
    return null;
  }

  static Uint8List encode({
    required List<Garment> garments,
    required Map<(String, PhotoVariant), Uint8List> photoFiles,
    required DateTime exportedAt,
    required int pendingOperations,
    BackupHistory history = BackupHistory.empty,
  }) {
    final files = <String, Uint8List>{
      BackupFormat.garmentsPath: utf8.encode(
        const JsonEncoder.withIndent(' ').convert({
          'garments': [for (final g in garments) garmentJson(g)],
        }),
      ),
      BackupFormat.historyPath: utf8.encode(
        const JsonEncoder.withIndent(' ').convert(historyJson(history)),
      ),
      for (final MapEntry(key: (id, variant), :value) in photoFiles.entries)
        BackupFormat.photoPath(id, variant): value,
    };
    final manifest = {
      'format': BackupFormat.name,
      'version': BackupFormat.version,
      'exported_at': GarmentRow.iso(exportedAt),
      'counts': {
        'garments': garments.length,
        'photos': photoFiles.length,
        'wear_events': history.wears.length,
        'cleaning_events': history.cleanings.length,
        'care_policies': history.policies.length,
      },
      'pending_operations': pendingOperations,
      'files': [
        for (final MapEntry(key: path, value: bytes) in files.entries)
          {
            'path': path,
            'mime': path.endsWith('.json') ? 'application/json' : 'image/jpeg',
            'size': bytes.length,
            'sha256': sha256.convert(bytes).toString(),
          },
      ],
    };

    final archive = Archive()
      ..add(
        ArchiveFile.bytes(
          BackupFormat.manifestPath,
          utf8.encode(const JsonEncoder.withIndent(' ').convert(manifest)),
        ),
      );
    for (final MapEntry(key: path, value: bytes) in files.entries) {
      // JPEG já vem comprimido: guardar tal como está poupa tempo.
      archive.add(
        ArchiveFile.bytes(path, bytes)
          ..compression = path.endsWith('.jpg')
              ? CompressionType.none
              : CompressionType.deflate,
      );
    }
    return ZipEncoder().encodeBytes(archive);
  }

  /// Lê e verifica tudo antes de devolver: versão, caminhos, tamanhos e
  /// hashes, peças e as fotografias que referem. Qualquer falha rejeita o
  /// ficheiro inteiro (nunca há importação parcial).
  static Result<BackupContents, BackupProblem> decode(Uint8List zip) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(zip, verify: true);
    } on Object {
      return const Err(NotABackup());
    }

    final manifestFile = archive.findFile(BackupFormat.manifestPath);
    if (manifestFile == null || manifestFile.size > BackupFormat.maxFileBytes) {
      return const Err(NotABackup());
    }
    final Object? manifest;
    try {
      manifest = jsonDecode(utf8.decode(manifestFile.content));
    } on Object {
      return const Err(NotABackup());
    }
    if (manifest is! Map<String, Object?> ||
        manifest['format'] != BackupFormat.name) {
      return const Err(NotABackup());
    }
    final version = manifest['version'];
    if (version is! int) return const Err(NotABackup());
    if (version > BackupFormat.version || version < 1) {
      return Err(UnsupportedBackupVersion(version));
    }
    final exportedAt = DateTime.tryParse('${manifest['exported_at']}');
    final pending = manifest['pending_operations'];
    final entries = manifest['files'];
    if (exportedAt == null || pending is! int || entries is! List) {
      return const Err(CorruptBackup('manifest'));
    }
    if (entries.length > BackupFormat.maxFiles) {
      return const Err(CorruptBackup('demasiados ficheiros'));
    }

    // Cada ficheiro: caminho seguro, presente, tamanho e hash certos.
    final contents = <String, Uint8List>{};
    var total = 0;
    for (final entry in entries) {
      if (entry case {
        'path': final String path,
        'size': final int size,
        'sha256': final String hash,
      }) {
        if (!_safePath.hasMatch(path) || contents.containsKey(path)) {
          return Err(CorruptBackup('caminho inválido: $path'));
        }
        final file = archive.findFile(path);
        total += size;
        if (file == null ||
            !file.isFile ||
            size > BackupFormat.maxFileBytes ||
            total > BackupFormat.maxTotalBytes ||
            file.size != size) {
          return Err(CorruptBackup('ficheiro em falta ou alterado: $path'));
        }
        final Uint8List bytes;
        try {
          bytes = file.content;
        } on Object {
          return Err(CorruptBackup('ficheiro ilegível: $path'));
        }
        if (bytes.length != size || sha256.convert(bytes).toString() != hash) {
          return Err(CorruptBackup('ficheiro alterado: $path'));
        }
        contents[path] = bytes;
      } else {
        return const Err(CorruptBackup('manifest'));
      }
    }
    for (final file in archive) {
      if (file.isFile &&
          file.name != BackupFormat.manifestPath &&
          !contents.containsKey(file.name)) {
        return Err(CorruptBackup('ficheiro inesperado: ${file.name}'));
      }
    }

    final garmentsBytes = contents[BackupFormat.garmentsPath];
    if (garmentsBytes == null) {
      return const Err(CorruptBackup('peças em falta'));
    }
    final Object? data;
    try {
      data = jsonDecode(utf8.decode(garmentsBytes));
    } on Object {
      return const Err(CorruptBackup('peças ilegíveis'));
    }
    final rawGarments = data is Map<String, Object?> ? data['garments'] : null;
    if (rawGarments is! List) return const Err(CorruptBackup('peças'));

    final garments = <Garment>[];
    final ids = <String>{};
    final photoFiles = <(String, PhotoVariant), Uint8List>{};
    for (final raw in rawGarments) {
      final garment = garmentFromJson(raw);
      if (garment == null || !ids.add(garment.id.value)) {
        return const Err(CorruptBackup('peça inválida'));
      }
      if (garment.photos.length > PhotoRules.maxPerGarment) {
        return const Err(CorruptBackup('fotografias a mais'));
      }
      for (final photo in garment.photos) {
        if (!_safeId.hasMatch(photo.id)) {
          return const Err(CorruptBackup('fotografia inválida'));
        }
        for (final variant in PhotoVariant.values) {
          final bytes = contents[BackupFormat.photoPath(photo.id, variant)];
          final expected = variant == PhotoVariant.main
              ? photo.bytes
              : photo.thumbBytes;
          if (bytes == null || bytes.length != expected) {
            return Err(CorruptBackup('fotografia em falta: ${photo.id}'));
          }
          if (variant == PhotoVariant.main &&
              sha256.convert(bytes).toString() != photo.sha256) {
            return Err(CorruptBackup('fotografia alterada: ${photo.id}'));
          }
          if (photoFiles.containsKey((photo.id, variant))) {
            return Err(CorruptBackup('fotografia repetida: ${photo.id}'));
          }
          photoFiles[(photo.id, variant)] = bytes;
        }
      }
      garments.add(garment);
    }
    // v1 não tinha histórico; a partir da v2 é obrigatório.
    var history = BackupHistory.empty;
    final historyBytes = contents[BackupFormat.historyPath];
    if (version >= 2 && historyBytes == null) {
      return const Err(CorruptBackup('histórico em falta'));
    }
    if (historyBytes != null) {
      final Object? raw;
      try {
        raw = jsonDecode(utf8.decode(historyBytes));
      } on Object {
        return const Err(CorruptBackup('histórico ilegível'));
      }
      final parsed = historyFromJson(raw, ids);
      if (parsed == null) return const Err(CorruptBackup('histórico'));
      history = parsed;
    }

    final expectedFiles =
        1 + (historyBytes == null ? 0 : 1) + photoFiles.length;
    if (contents.length != expectedFiles) {
      return const Err(CorruptBackup('ficheiros sem peça'));
    }

    return Ok(
      BackupContents(
        summary: BackupSummary(
          exportedAt: exportedAt.toUtc(),
          garments: garments.length,
          photos: photoFiles.length ~/ PhotoVariant.values.length,
          pendingOperations: pending,
          wears: history.wears.length,
          cleanings: history.cleanings.length,
        ),
        garments: List.unmodifiable(garments),
        photoFiles: Map.unmodifiable(photoFiles),
        history: history,
      ),
    );
  }

  static final _safeId = RegExp(r'^[A-Za-z0-9-]{1,64}$');

  /// Relativo, sem `..`, só os caracteres que a app usa.
  static final _safePath = RegExp(
    r'^(data/[a-z_]+\.json|photos/[A-Za-z0-9-]{1,64}/(main|thumb)\.jpg)$',
  );
}
