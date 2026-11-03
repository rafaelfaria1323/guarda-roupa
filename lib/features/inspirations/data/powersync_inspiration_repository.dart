import 'dart:convert';

import 'package:powersync/powersync.dart';
import 'package:sqlite3/common.dart' show SqliteException;
import 'package:sqlite_async/sqlite_async.dart';

import '../../../core/domain/clock.dart';
import '../../../core/domain/result.dart';
import '../../wardrobe/data/garment_row.dart';
import '../../wardrobe/domain/garment_attributes.dart';
import '../domain/inspiration.dart';
import '../domain/inspiration_repository.dart';

/// Inspirações sobre o SQLite do PowerSync: `inspirations` é a visão
/// otimista local e `style_operations` a fila para `apply_style_operation`.
final class PowerSyncInspirationRepository implements InspirationRepository {
  PowerSyncInspirationRepository({
    required this._db,
    required this._ownerId,
    this._clock = const SystemClock(),
  });

  final PowerSyncDatabase _db;
  final String _ownerId;
  final Clock _clock;

  static const _tables = {'inspirations'};

  @override
  Stream<List<Inspiration>> watchInspirations() => _db
      .watch(
        'SELECT * FROM inspirations WHERE deleted_at IS NULL '
        'ORDER BY created_at DESC, id',
        triggerOnTables: _tables,
      )
      .map((rows) => [for (final row in rows) ?fromRow(row)]);

  @override
  Stream<Inspiration?> watchInspiration(String id) => _db
      .watch(
        'SELECT * FROM inspirations WHERE id = ? AND deleted_at IS NULL',
        parameters: [id],
        triggerOnTables: _tables,
      )
      .map((rows) => rows.isEmpty ? null : fromRow(rows.first));

  @override
  Future<InspirationResult<Inspiration>> createInspiration(
    InspirationDraft draft,
  ) {
    final d = draft.normalized();
    if (InspirationRules.validate(d) case final problem?) {
      return Future.value(Err(InvalidInspiration(problem)));
    }
    return _guard(
      () => _db.writeTransaction((tx) async {
        final id = (await tx.get('SELECT uuid() AS id'))['id']! as String;
        final now = _clock.nowUtc();
        final fields = columns(d);
        await tx.execute(
          'INSERT INTO inspirations (id, owner_id, ${fields.keys.join(', ')}, '
          'created_at, updated_at) VALUES (?, ?, '
          '${List.filled(fields.length, '?').join(', ')}, ?, ?)',
          [
            id,
            _ownerId,
            for (final v in fields.values) _sqlValue(v),
            GarmentRow.iso(now),
            GarmentRow.iso(now),
          ],
        );
        await _operation(tx, id, 'create_inspiration', {
          for (final MapEntry(:key, :value) in fields.entries)
            if (value != null && !(value is List && value.isEmpty)) key: value,
        });
        return Ok(_build(id, d, now, now));
      }),
    );
  }

  @override
  Future<InspirationResult<Inspiration>> updateInspiration(
    String id,
    InspirationDraft draft,
  ) {
    final d = draft.normalized();
    if (InspirationRules.validate(d) case final problem?) {
      return Future.value(Err(InvalidInspiration(problem)));
    }
    return _guard(
      () => _db.writeTransaction((tx) async {
        final row = await tx.getOptional(
          'SELECT * FROM inspirations WHERE id = ? AND deleted_at IS NULL',
          [id],
        );
        final current = row == null ? null : fromRow(row);
        if (current == null) return Err(InspirationNotFound(id));

        // Só os campos que mudaram: o servidor junta campo a campo.
        final before = columns(current.toDraft());
        final after = columns(d);
        final changes = {
          for (final MapEntry(:key, :value) in after.entries)
            if (jsonEncode(value) != jsonEncode(before[key])) key: value,
        };
        if (changes.isEmpty) return Ok(current);
        final now = _clock.nowUtc();
        await tx.execute(
          'UPDATE inspirations SET '
          '${[for (final k in changes.keys) '$k = ?'].join(', ')}, '
          'updated_at = ? WHERE id = ?',
          [
            for (final v in changes.values) _sqlValue(v),
            GarmentRow.iso(now),
            id,
          ],
        );
        await _operation(tx, id, 'edit_inspiration', changes);
        return Ok(_build(id, d, current.createdAt, now));
      }),
    );
  }

  @override
  Future<InspirationResult<void>> deleteInspiration(String id) => _guard(
    () => _db.writeTransaction((tx) async {
      final row = await tx.getOptional(
        'SELECT deleted_at FROM inspirations WHERE id = ?',
        [id],
      );
      if (row == null) return Err(InspirationNotFound(id));
      if (row['deleted_at'] == null) {
        final now = GarmentRow.iso(_clock.nowUtc());
        await tx.execute(
          'UPDATE inspirations SET deleted_at = ?, updated_at = ? '
          'WHERE id = ?',
          [now, now, id],
        );
        await _operation(tx, id, 'delete_inspiration', const {});
      }
      return const Ok(null);
    }),
  );

  /// Colunas do servidor, com listas como listas (ordem estável).
  static Map<String, Object?> columns(InspirationDraft d) => {
    'title': d.title,
    'source_url': d.sourceUrl,
    'notes': d.notes,
    'palette': d.palette,
    'formality': d.formality?.id,
    'patterns': [
      for (final p in GarmentPattern.values)
        if (d.patterns.contains(p)) p.id,
    ],
    'textures': [
      for (final t in SurfaceTexture.values)
        if (d.textures.contains(t)) t.id,
    ],
    'occasions': [
      for (final o in Occasion.values)
        if (d.occasions.contains(o)) o.id,
    ],
  };

  static Object? _sqlValue(Object? v) => v is List ? jsonEncode(v) : v;

  static Inspiration _build(
    String id,
    InspirationDraft d,
    DateTime created,
    DateTime updated,
  ) => Inspiration(
    id: id,
    title: d.title,
    sourceUrl: d.sourceUrl,
    notes: d.notes,
    palette: List.unmodifiable(d.palette),
    formality: d.formality,
    patterns: d.patterns,
    textures: d.textures,
    occasions: d.occasions,
    createdAt: created,
    updatedAt: updated,
  );

  Future<void> _operation(
    SqliteWriteContext tx,
    String entityId,
    String kind,
    Map<String, Object?> data,
  ) => tx.execute(
    'INSERT INTO style_operations (id, entity_id, kind, data, created_at) '
    'VALUES (uuid(), ?, ?, ?, ?)',
    [entityId, kind, jsonEncode(data), GarmentRow.iso(_clock.nowUtc())],
  );

  /// Linhas inválidas ficam de fora; etiquetas desconhecidas (ex.: de uma
  /// versão futura) são ignoradas.
  static Inspiration? fromRow(Map<String, Object?> row) {
    final created = DateTime.tryParse(row['created_at'] as String? ?? '');
    final updated = DateTime.tryParse(row['updated_at'] as String? ?? '');
    if (created == null || updated == null) return null;
    final title = row['title'] as String?;
    final url = row['source_url'] as String?;
    if (title == null && url == null) return null;
    List<Object?> list(String key) => switch (_decode(row[key])) {
      final List<Object?> l => l,
      _ => const [],
    };
    return Inspiration(
      id: row['id']! as String,
      title: title,
      sourceUrl: url,
      notes: row['notes'] as String?,
      palette: List.unmodifiable([
        for (final c in list('palette'))
          if (c is int && c >= 0 && c <= 0xFFFFFF) c,
      ]),
      formality: Formality.fromId(row['formality'] as String?),
      patterns: {
        for (final p in list('patterns'))
          if (p is String) ?GarmentPattern.fromId(p),
      },
      textures: {
        for (final t in list('textures'))
          if (t is String) ?SurfaceTexture.fromId(t),
      },
      occasions: {
        for (final o in list('occasions'))
          if (o is String) ?Occasion.fromId(o),
      },
      createdAt: created,
      updatedAt: updated,
    );
  }

  static Object? _decode(Object? text) {
    if (text is! String) return null;
    try {
      return jsonDecode(text);
    } on FormatException {
      return null;
    }
  }

  static Future<InspirationResult<T>> _guard<T>(
    Future<InspirationResult<T>> Function() action,
  ) async {
    try {
      return await action();
    } on SqliteException catch (e) {
      return Err(InspirationStorageFailure(e.message));
    }
  }
}
