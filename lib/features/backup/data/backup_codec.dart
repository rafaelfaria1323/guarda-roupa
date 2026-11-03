import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

import '../../../core/domain/result.dart';
import '../../care/domain/care_policies.dart';
import '../../care/domain/cleaning_event.dart';
import '../../inspirations/data/powersync_inspiration_repository.dart';
import '../../inspirations/domain/inspiration.dart';
import '../../inspirations/domain/style_preference.dart';
import '../../outfits/domain/outfit.dart';
import '../../wardrobe/data/garment_row.dart';
import '../../wardrobe/domain/garment.dart';
import '../../wardrobe/domain/garment_attributes.dart';
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

  /// `data/outfits.json`.
  static Map<String, Object?> outfitsJson(List<Outfit> outfits) => {
    'outfits': [
      for (final o in outfits)
        {
          'id': o.id,
          'name': o.name,
          'occasions': [
            for (final occasion in Occasion.values)
              if (o.occasions.contains(occasion)) occasion.id,
          ],
          'items': [
            for (final i in o.items)
              {'garment_id': i.garmentId.value, 'role': i.role.id},
          ],
          'created_at': GarmentRow.iso(o.createdAt),
          'updated_at': GarmentRow.iso(o.updatedAt),
        },
    ],
  };

  /// Inverso de [outfitsJson]; `null` se um conjunto for inválido (as
  /// mesmas regras do servidor) ou referir uma peça que não está no backup.
  static List<Outfit>? outfitsFromJson(Object? json, Set<String> garments) {
    if (json case {'outfits': final List<Object?> raw}) {
      final ids = <String>{};
      final outfits = <Outfit>[];
      for (final o in raw) {
        if (o
            case {
              'id': final String id,
              'name': final Object? name,
              'occasions': final List<Object?> rawOccasions,
              'items': final List<Object?> rawItems,
              'created_at': final String createdAt,
              'updated_at': final String updatedAt,
            }
            when _safeId.hasMatch(id) && ids.add(id)) {
          final created = DateTime.tryParse(createdAt);
          final updated = DateTime.tryParse(updatedAt);
          if (created == null || updated == null) return null;
          if (name != null && (name is! String || name.trim().isEmpty)) {
            return null;
          }
          final occasions = <Occasion>{
            for (final x in rawOccasions)
              if (x is String) ?Occasion.fromId(x),
          };
          if (occasions.length != rawOccasions.length) return null;
          final items = <OutfitItem>[];
          for (final item in rawItems) {
            if (item
                case {
                  'garment_id': final String garment,
                  'role': final String roleId,
                }
                when item.length == 2 && garments.contains(garment)) {
              final role = OutfitRole.fromId(roleId);
              if (role == null) return null;
              items.add(OutfitItem(GarmentId(garment), role));
            } else {
              return null;
            }
          }
          final outfit = Outfit(
            id: id,
            name: name as String?,
            occasions: occasions,
            items: List.unmodifiable(items),
            createdAt: created.toUtc(),
            updatedAt: updated.toUtc(),
          );
          if (OutfitRules.validate(outfit.toDraft()) != null) return null;
          outfits.add(outfit);
        } else {
          return null;
        }
      }
      return List.unmodifiable(outfits);
    }
    return null;
  }

  /// `data/style.json`: inspirações e preferências.
  static Map<String, Object?> styleJson(
    List<Inspiration> inspirations,
    List<StylePreference> preferences,
  ) => {
    'inspirations': [
      for (final i in inspirations)
        {
          'id': i.id,
          ...PowerSyncInspirationRepository.columns(i.toDraft()),
          'created_at': GarmentRow.iso(i.createdAt),
          'updated_at': GarmentRow.iso(i.updatedAt),
        },
    ],
    'preferences': [
      for (final p in preferences)
        {
          'id': p.id,
          'subject': p.subject.id,
          'value': p.value,
          'stance': p.stance.id,
          'occasions': [
            for (final o in Occasion.values)
              if (p.occasions.contains(o)) o.id,
          ],
          'inspiration_id': p.inspirationId,
          'created_at': GarmentRow.iso(p.createdAt),
          'updated_at': GarmentRow.iso(p.updatedAt),
        },
    ],
  };

  /// Inverso de [styleJson]; `null` se algo for inválido (as mesmas regras
  /// do servidor) ou se uma preferência referir uma inspiração que não está
  /// no ficheiro.
  static (List<Inspiration>, List<StylePreference>)? styleFromJson(
    Object? json,
  ) {
    if (json case {
      'inspirations': final List<Object?> rawInspirations,
      'preferences': final List<Object?> rawPreferences,
    }) {
      final inspirations = <Inspiration>[];
      final ids = <String>{};
      for (final i in rawInspirations) {
        final parsed = _inspirationFromJson(i);
        if (parsed == null || !ids.add(parsed.id)) return null;
        inspirations.add(parsed);
      }
      final preferences = <StylePreference>[];
      final prefIds = <String>{};
      for (final p in rawPreferences) {
        final parsed = _preferenceFromJson(p);
        if (parsed == null || !prefIds.add(parsed.id)) return null;
        if (parsed.inspirationId case final origin?
            when !ids.contains(origin)) {
          return null;
        }
        preferences.add(parsed);
      }
      return (List.unmodifiable(inspirations), List.unmodifiable(preferences));
    }
    return null;
  }

  static Inspiration? _inspirationFromJson(Object? json) {
    if (json
        case {
          'id': final String id,
          'title': final String? title,
          'source_url': final String? sourceUrl,
          'notes': final String? notes,
          'palette': final List<Object?> rawPalette,
          'formality': final String? rawFormality,
          'patterns': final List<Object?> rawPatterns,
          'textures': final List<Object?> rawTextures,
          'occasions': final List<Object?> rawOccasions,
          'created_at': final String createdAt,
          'updated_at': final String updatedAt,
        }
        when _safeId.hasMatch(id)) {
      final created = DateTime.tryParse(createdAt);
      final updated = DateTime.tryParse(updatedAt);
      if (created == null || updated == null) return null;
      final palette = [
        for (final c in rawPalette)
          if (c is int && c >= 0 && c <= 0xFFFFFF) c,
      ];
      final formality = Formality.fromId(rawFormality);
      final patterns = _known(rawPatterns, GarmentPattern.fromId);
      final textures = _known(rawTextures, SurfaceTexture.fromId);
      final occasions = _known(rawOccasions, Occasion.fromId);
      // Proporções vieram depois do v4: ausentes = nenhuma.
      final proportions = switch (json['proportions']) {
        null => const <Proportion>{},
        final List<Object?> raw => _known(raw, Proportion.fromId),
        _ => null,
      };
      if (palette.length != rawPalette.length ||
          (rawFormality != null && formality == null) ||
          patterns == null ||
          textures == null ||
          occasions == null ||
          proportions == null) {
        return null;
      }
      final draft = InspirationDraft(
        title: title,
        sourceUrl: sourceUrl,
        notes: notes,
        palette: palette,
        formality: formality,
        patterns: patterns,
        textures: textures,
        occasions: occasions,
        proportions: proportions,
      );
      // Já guardado normalizado: o ficheiro não pode trazer outra coisa.
      final normalized = draft.normalized();
      if (normalized.title != title ||
          normalized.sourceUrl != sourceUrl ||
          normalized.notes != notes ||
          InspirationRules.validate(normalized) != null) {
        return null;
      }
      return Inspiration(
        id: id,
        title: title,
        sourceUrl: sourceUrl,
        notes: notes,
        palette: List.unmodifiable(palette),
        formality: formality,
        patterns: patterns,
        textures: textures,
        occasions: occasions,
        proportions: proportions,
        createdAt: created.toUtc(),
        updatedAt: updated.toUtc(),
      );
    }
    return null;
  }

  static StylePreference? _preferenceFromJson(Object? json) {
    if (json
        case {
          'id': final String id,
          'subject': final String rawSubject,
          'value': final String value,
          'stance': final String rawStance,
          'occasions': final List<Object?> rawOccasions,
          'inspiration_id': final String? inspirationId,
          'created_at': final String createdAt,
          'updated_at': final String updatedAt,
        }
        when _safeId.hasMatch(id)) {
      final subject = PreferenceSubject.fromId(rawSubject);
      final stance = PreferenceStance.fromId(rawStance);
      final occasions = _known(rawOccasions, Occasion.fromId);
      final created = DateTime.tryParse(createdAt);
      final updated = DateTime.tryParse(updatedAt);
      if (subject == null ||
          !subject.accepts(value) ||
          stance == null ||
          occasions == null ||
          created == null ||
          updated == null) {
        return null;
      }
      return StylePreference(
        id: id,
        subject: subject,
        value: value,
        stance: stance,
        occasions: occasions,
        inspirationId: inspirationId,
        createdAt: created.toUtc(),
        updatedAt: updated.toUtc(),
      );
    }
    return null;
  }

  /// Ids conhecidos e sem repetidos; `null` se algum não for.
  static Set<T>? _known<T>(List<Object?> raw, T? Function(String) fromId) {
    final out = <T>{
      for (final x in raw)
        if (x is String) ?fromId(x),
    };
    return out.length == raw.length ? out : null;
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
      BackupFormat.outfitsPath: utf8.encode(
        const JsonEncoder.withIndent(' ').convert(outfitsJson(history.outfits)),
      ),
      BackupFormat.stylePath: utf8.encode(
        const JsonEncoder.withIndent(' ')
            .convert(styleJson(history.inspirations, history.preferences)),
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
        'outfits': history.outfits.length,
        'inspirations': history.inspirations.length,
        'style_preferences': history.preferences.length,
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
    // Conjuntos: obrigatórios a partir da v3.
    final outfitsBytes = contents[BackupFormat.outfitsPath];
    if (version >= 3 && outfitsBytes == null) {
      return const Err(CorruptBackup('conjuntos em falta'));
    }
    if (outfitsBytes != null) {
      final Object? raw;
      try {
        raw = jsonDecode(utf8.decode(outfitsBytes));
      } on Object {
        return const Err(CorruptBackup('conjuntos ilegíveis'));
      }
      final outfits = outfitsFromJson(raw, ids);
      if (outfits == null) return const Err(CorruptBackup('conjuntos'));
      history = history.withOutfits(outfits);
    }
    // Inspirações e preferências: obrigatórias a partir da v4.
    final styleBytes = contents[BackupFormat.stylePath];
    if (version >= 4 && styleBytes == null) {
      return const Err(CorruptBackup('estilo em falta'));
    }
    if (styleBytes != null) {
      final Object? raw;
      try {
        raw = jsonDecode(utf8.decode(styleBytes));
      } on Object {
        return const Err(CorruptBackup('estilo ilegível'));
      }
      final style = styleFromJson(raw);
      if (style == null) return const Err(CorruptBackup('estilo'));
      history = history.withStyle(style.$1, style.$2);
    }

    final expectedFiles =
        1 +
        (historyBytes == null ? 0 : 1) +
        (outfitsBytes == null ? 0 : 1) +
        (styleBytes == null ? 0 : 1) +
        photoFiles.length;
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
          outfits: history.outfits.length,
          inspirations: history.inspirations.length,
          preferences: history.preferences.length,
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
