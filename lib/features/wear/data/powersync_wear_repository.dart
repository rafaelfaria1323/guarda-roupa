import 'dart:convert';

import 'package:powersync/powersync.dart';
import 'package:sqlite3/common.dart' show SqliteException;
import 'package:sqlite_async/sqlite_async.dart';

import '../../../core/domain/clock.dart';
import '../../../core/domain/result.dart';
import '../../wardrobe/data/garment_row.dart';
import '../../wardrobe/domain/garment.dart';
import '../domain/calendar_day.dart';
import '../domain/wear_event.dart';
import '../domain/wear_repository.dart';

/// Utilizações sobre o SQLite do PowerSync: `wear_events` é a visão
/// otimista local e `wear_operations` a fila para `apply_wear_operation`.
final class PowerSyncWearRepository implements WearRepository {
  PowerSyncWearRepository({
    required this._db,
    required this._ownerId,
    this._clock = const SystemClock(),
  });

  final PowerSyncDatabase _db;
  final String _ownerId;
  final Clock _clock;

  static const _tables = {'wear_events'};

  @override
  Stream<List<WearEvent>> watchAll() => _db
      .watch(
        'SELECT * FROM wear_events WHERE voided_at IS NULL '
        'ORDER BY worn_on, created_at, id',
        triggerOnTables: _tables,
      )
      .map(_events);

  @override
  Stream<List<WearEvent>> watchDay(CalendarDay day) => _db
      .watch(
        'SELECT * FROM wear_events WHERE worn_on = ? AND voided_at IS NULL '
        'ORDER BY created_at, id',
        parameters: [day.iso],
        triggerOnTables: _tables,
      )
      .map(_events);

  @override
  Stream<WearEvent?> watchEvent(String id) => _db
      .watch(
        'SELECT * FROM wear_events WHERE id = ? AND voided_at IS NULL',
        parameters: [id],
        triggerOnTables: _tables,
      )
      .map((rows) => rows.isEmpty ? null : _event(rows.first));

  @override
  Stream<List<WearEvent>> watchGarmentHistory(GarmentId id) => _db
      .watch(
        'SELECT * FROM wear_events WHERE voided_at IS NULL AND EXISTS '
        '(SELECT 1 FROM json_each(garment_ids) WHERE value = ?) '
        'ORDER BY worn_on DESC, created_at DESC, id',
        parameters: [id.value],
        triggerOnTables: _tables,
      )
      .map(_events);

  @override
  Future<WearResult<WearEvent>> recordWear(
    CalendarDay day,
    Set<GarmentId> garments, {
    String? planEntryId,
  }) => _guard(
    () => _db.writeTransaction(
      (tx) => _record(tx, day, garments, planEntryId: planEntryId),
    ),
  );

  @override
  Future<WearResult<WearEvent>> correctWear(
    String eventId,
    Set<GarmentId> garments,
  ) => _guard(
    () => _db.writeTransaction((tx) async {
      final current = await _find(tx, eventId);
      if (current == null) return Err(WearNotFound(eventId));
      final problem = await _validate(tx, current.wornOn, garments);
      if (problem != null) return Err(InvalidWear(problem));
      await _void(tx, eventId);
      return _record(
        tx,
        current.wornOn,
        garments,
        planEntryId: current.planEntryId,
      );
    }),
  );

  @override
  Future<WearResult<void>> voidWear(String eventId) => _guard(
    () => _db.writeTransaction((tx) async {
      final row = await tx.getOptional(
        'SELECT voided_at FROM wear_events WHERE id = ?',
        [eventId],
      );
      if (row == null) return Err(WearNotFound(eventId));
      if (row['voided_at'] == null) await _void(tx, eventId);
      return const Ok(null);
    }),
  );

  Future<WearResult<WearEvent>> _record(
    SqliteWriteContext tx,
    CalendarDay day,
    Set<GarmentId> garments, {
    String? planEntryId,
  }) async {
    final problem = await _validate(tx, day, garments);
    if (problem != null) return Err(InvalidWear(problem));

    final id = (await tx.get('SELECT uuid() AS id'))['id']! as String;
    final now = _clock.nowUtc();
    final ids = [for (final g in garments) g.value];
    await tx.execute(
      'INSERT INTO wear_events (id, owner_id, worn_on, garment_ids, '
      'plan_entry_id, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
      [
        id,
        _ownerId,
        day.iso,
        jsonEncode(ids),
        planEntryId,
        GarmentRow.iso(now),
        GarmentRow.iso(now),
      ],
    );
    await _operation(tx, id, 'record_wear', {
      'worn_on': day.iso,
      'garment_ids': ids,
      'plan_entry_id': ?planEntryId,
    });
    return Ok(
      WearEvent(
        id: id,
        wornOn: day,
        garmentIds: garments.toList(),
        planEntryId: planEntryId,
        createdAt: now,
      ),
    );
  }

  Future<WearProblem?> _validate(
    SqliteReadContext tx,
    CalendarDay day,
    Set<GarmentId> garments,
  ) async {
    if (garments.isEmpty) return WearProblem.noGarments;
    if (garments.length > WearRules.maxGarments) {
      return WearProblem.tooManyGarments;
    }
    if (day.isAfter(CalendarDay.of(_clock.nowUtc()))) {
      return WearProblem.futureDay;
    }
    final ids = [for (final g in garments) g.value];
    // Arquivadas contam: o registo pode ser tardio.
    final known = await tx.get(
      'SELECT count(*) AS n FROM garments WHERE deleted_at IS NULL '
      'AND id IN (SELECT value FROM json_each(?))',
      [jsonEncode(ids)],
    );
    if (known['n'] != ids.length) return WearProblem.unknownGarment;
    return null;
  }

  Future<void> _void(SqliteWriteContext tx, String eventId) async {
    final now = GarmentRow.iso(_clock.nowUtc());
    await tx.execute(
      'UPDATE wear_events SET voided_at = ?, updated_at = ? WHERE id = ?',
      [now, now, eventId],
    );
    await _operation(tx, eventId, 'void_wear', const {});
  }

  /// Fila partilhada com limpezas e políticas (`apply_wear_operation`).
  Future<void> _operation(
    SqliteWriteContext tx,
    String eventId,
    String kind,
    Map<String, Object?> data,
  ) => tx.execute(
    'INSERT INTO wear_operations (id, event_id, kind, data, created_at) '
    'VALUES (uuid(), ?, ?, ?, ?)',
    [eventId, kind, jsonEncode(data), GarmentRow.iso(_clock.nowUtc())],
  );

  static Future<WearEvent?> _find(SqliteReadContext tx, String id) async {
    final row = await tx.getOptional(
      'SELECT * FROM wear_events WHERE id = ? AND voided_at IS NULL',
      [id],
    );
    return row == null ? null : _event(row);
  }

  static List<WearEvent> _events(List<Map<String, Object?>> rows) => [
    for (final row in rows) ?_event(row),
  ];

  /// Para quem lê `wear_events` diretamente (ex.: backup).
  static WearEvent? fromRow(Map<String, Object?> row) => _event(row);

  /// Linhas inválidas (ex.: de uma versão futura) ficam de fora.
  static WearEvent? _event(Map<String, Object?> row) {
    final day = CalendarDay.tryParse(row['worn_on'] as String?);
    final created = DateTime.tryParse(row['created_at'] as String? ?? '');
    final ids = switch (jsonDecode(row['garment_ids'] as String? ?? 'null')) {
      final List<Object?> list => [
        for (final v in list)
          if (v is String) GarmentId(v),
      ],
      _ => null,
    };
    if (day == null || created == null || ids == null || ids.isEmpty) {
      return null;
    }
    return WearEvent(
      id: row['id']! as String,
      wornOn: day,
      garmentIds: ids,
      planEntryId: row['plan_entry_id'] as String?,
      createdAt: created,
    );
  }

  static Future<WearResult<T>> _guard<T>(
    Future<WearResult<T>> Function() action,
  ) async {
    try {
      return await action();
    } on SqliteException catch (e) {
      return Err(WearStorageFailure(e.message));
    }
  }
}
