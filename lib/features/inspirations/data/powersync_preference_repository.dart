import 'dart:convert';

import 'package:powersync/powersync.dart';
import 'package:sqlite3/common.dart' show SqliteException;
import 'package:sqlite_async/sqlite_async.dart';

import '../../../core/domain/clock.dart';
import '../../../core/domain/result.dart';
import '../../wardrobe/data/garment_row.dart';
import '../../wardrobe/domain/garment_attributes.dart';
import '../domain/inspiration_repository.dart';
import '../domain/style_preference.dart';

/// Preferências sobre o SQLite do PowerSync: `style_preferences` é a visão
/// otimista local; as operações vão em `style_operations`.
final class PowerSyncPreferenceRepository implements StylePreferenceRepository {
  PowerSyncPreferenceRepository({
    required this._db,
    required this._ownerId,
    this._clock = const SystemClock(),
  });

  final PowerSyncDatabase _db;
  final String _ownerId;
  final Clock _clock;

  static const _tables = {'style_preferences'};

  @override
  Stream<List<StylePreference>> watchPreferences() => _db
      .watch(
        'SELECT * FROM style_preferences WHERE deleted_at IS NULL '
        'ORDER BY created_at DESC, id',
        triggerOnTables: _tables,
      )
      .map((rows) => [for (final row in rows) ?fromRow(row)]);

  @override
  Stream<StylePreference?> watchPreference(String id) => _db
      .watch(
        'SELECT * FROM style_preferences WHERE id = ? AND deleted_at IS NULL',
        parameters: [id],
        triggerOnTables: _tables,
      )
      .map((rows) => rows.isEmpty ? null : fromRow(rows.first));

  @override
  Future<PreferenceResult<StylePreference>> createPreference(
    PreferenceDraft draft,
  ) {
    if (!draft.subject.accepts(draft.value)) {
      return Future.value(const Err(InvalidPreference()));
    }
    return _guard(
      () => _db.writeTransaction((tx) async {
        if (await _sameTarget(tx, draft, except: null) case final id?) {
          return Err(DuplicatePreference(id));
        }
        return Ok(await _insert(tx, draft));
      }),
    );
  }

  @override
  Future<PreferenceResult<int>> createPreferences(
    List<PreferenceDraft> drafts,
  ) {
    if (drafts.any((d) => !d.subject.accepts(d.value))) {
      return Future.value(const Err(InvalidPreference()));
    }
    return _guard(
      () => _db.writeTransaction((tx) async {
        var created = 0;
        for (final d in drafts) {
          if (await _sameTarget(tx, d, except: null) != null) continue;
          await _insert(tx, d);
          created++;
        }
        return Ok(created);
      }),
    );
  }

  @override
  Future<PreferenceResult<StylePreference>> updatePreference(
    String id,
    PreferenceDraft draft,
  ) => _guard(
    () => _db.writeTransaction((tx) async {
      final row = await tx.getOptional(
        'SELECT * FROM style_preferences WHERE id = ? AND deleted_at IS NULL',
        [id],
      );
      final current = row == null ? null : fromRow(row);
      if (current == null) return Err(PreferenceNotFound(id));
      // O assunto e a origem não mudam.
      final next = PreferenceDraft(
        subject: current.subject,
        value: draft.value,
        stance: draft.stance,
        occasions: draft.occasions,
        inspirationId: current.inspirationId,
      );
      if (!next.subject.accepts(next.value)) {
        return const Err(InvalidPreference());
      }
      if (await _sameTarget(tx, next, except: id) case final other?) {
        return Err(DuplicatePreference(other));
      }
      final occasions = _occasionsJson(next.occasions);
      final changes = <String, Object?>{
        if (next.value != current.value) 'value': next.value,
        if (next.stance != current.stance) 'stance': next.stance.id,
        if (jsonEncode(occasions) !=
            jsonEncode(_occasionsJson(current.occasions)))
          'occasions': occasions,
      };
      if (changes.isEmpty) return Ok(current);
      final now = _clock.nowUtc();
      await tx.execute(
        'UPDATE style_preferences SET value = ?, stance = ?, occasions = ?, '
        'updated_at = ? WHERE id = ?',
        [
          next.value,
          next.stance.id,
          jsonEncode(occasions),
          GarmentRow.iso(now),
          id,
        ],
      );
      await _operation(tx, id, 'edit_preference', changes);
      return Ok(_build(id, next, current.createdAt, now));
    }),
  );

  @override
  Future<PreferenceResult<void>> deletePreference(String id) => _guard(
    () => _db.writeTransaction((tx) async {
      final row = await tx.getOptional(
        'SELECT deleted_at FROM style_preferences WHERE id = ?',
        [id],
      );
      if (row == null) return Err(PreferenceNotFound(id));
      if (row['deleted_at'] == null) {
        final now = GarmentRow.iso(_clock.nowUtc());
        await tx.execute(
          'UPDATE style_preferences SET deleted_at = ?, updated_at = ? '
          'WHERE id = ?',
          [now, now, id],
        );
        await _operation(tx, id, 'delete_preference', const {});
      }
      return const Ok(null);
    }),
  );

  Future<StylePreference> _insert(
    SqliteWriteContext tx,
    PreferenceDraft d,
  ) async {
    final id = (await tx.get('SELECT uuid() AS id'))['id']! as String;
    final now = _clock.nowUtc();
    final occasions = _occasionsJson(d.occasions);
    await tx.execute(
      'INSERT INTO style_preferences (id, owner_id, subject, value, stance, '
      'occasions, inspiration_id, created_at, updated_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        id,
        _ownerId,
        d.subject.id,
        d.value,
        d.stance.id,
        jsonEncode(occasions),
        d.inspirationId,
        GarmentRow.iso(now),
        GarmentRow.iso(now),
      ],
    );
    await _operation(tx, id, 'create_preference', {
      'subject': d.subject.id,
      'value': d.value,
      'stance': d.stance.id,
      if (occasions.isNotEmpty) 'occasions': occasions,
      'inspiration_id': ?d.inspirationId,
    });
    return _build(id, d, now, now);
  }

  /// Id de uma preferência ativa com o mesmo assunto, valor e contexto.
  static Future<String?> _sameTarget(
    SqliteReadContext tx,
    PreferenceDraft d, {
    required String? except,
  }) async {
    final rows = await tx.getAll(
      'SELECT * FROM style_preferences WHERE deleted_at IS NULL '
      'AND subject = ? AND value = ? AND id IS NOT ?',
      [d.subject.id, d.value, except],
    );
    for (final row in rows) {
      if (fromRow(row) case final p? when p.toDraft().sameTarget(d)) {
        return p.id;
      }
    }
    return null;
  }

  static List<String> _occasionsJson(Set<Occasion> occasions) => [
    for (final o in Occasion.values)
      if (occasions.contains(o)) o.id,
  ];

  static StylePreference _build(
    String id,
    PreferenceDraft d,
    DateTime created,
    DateTime updated,
  ) => StylePreference(
    id: id,
    subject: d.subject,
    value: d.value,
    stance: d.stance,
    occasions: d.occasions,
    inspirationId: d.inspirationId,
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

  /// Linhas com assunto, valor ou posição desconhecidos ficam de fora.
  static StylePreference? fromRow(Map<String, Object?> row) {
    final subject = PreferenceSubject.fromId(row['subject'] as String?);
    final value = row['value'] as String?;
    final stance = PreferenceStance.fromId(row['stance'] as String?);
    final created = DateTime.tryParse(row['created_at'] as String? ?? '');
    final updated = DateTime.tryParse(row['updated_at'] as String? ?? '');
    if (subject == null ||
        value == null ||
        !subject.accepts(value) ||
        stance == null ||
        created == null ||
        updated == null) {
      return null;
    }
    final occasions = switch (_decode(row['occasions'])) {
      final List<Object?> list => {
        for (final o in list)
          if (o is String) ?Occasion.fromId(o),
      },
      _ => <Occasion>{},
    };
    return StylePreference(
      id: row['id']! as String,
      subject: subject,
      value: value,
      stance: stance,
      occasions: occasions,
      inspirationId: row['inspiration_id'] as String?,
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

  static Future<PreferenceResult<T>> _guard<T>(
    Future<PreferenceResult<T>> Function() action,
  ) async {
    try {
      return await action();
    } on SqliteException catch (e) {
      return Err(PreferenceStorageFailure(e.message));
    }
  }
}
