import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:powersync/powersync.dart';
import 'package:sqlite3/common.dart' show SqliteException;
import 'package:sqlite_async/sqlite_async.dart';

import '../../../core/domain/clock.dart';
import '../../../core/domain/result.dart';
import '../../wardrobe/data/garment_row.dart';
import '../../wardrobe/domain/garment.dart';
import '../../wardrobe/domain/garment_category.dart';
import '../../wear/domain/calendar_day.dart';
import '../domain/care_policies.dart';
import '../domain/care_repository.dart';
import '../domain/cleaning_event.dart';

/// Limpezas e valores escolhidos sobre o SQLite do PowerSync. As operações
/// seguem na fila `wear_operations` para `apply_wear_operation`.
final class PowerSyncCareRepository implements CareRepository {
  PowerSyncCareRepository({
    required this._db,
    required this._ownerId,
    this._clock = const SystemClock(),
  });

  final PowerSyncDatabase _db;
  final String _ownerId;
  final Clock _clock;

  /// Igual ao servidor: `md5(dono:âmbito:alvo)` em forma de UUID, para que
  /// o mesmo valor escolhido em dois dispositivos seja a mesma linha.
  static String policyId(String ownerId, PolicyScope scope, String target) {
    final h = md5
        .convert(utf8.encode('$ownerId:${scope.id}:$target'))
        .toString();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
        '${h.substring(16, 20)}-${h.substring(20)}';
  }

  @override
  Stream<List<CleaningEvent>> watchCleanings() => _db
      .watch(
        'SELECT * FROM cleaning_events WHERE voided_at IS NULL '
        'ORDER BY cleaned_on, created_at, id',
        triggerOnTables: const {'cleaning_events'},
      )
      .map((rows) => [for (final row in rows) ?_cleaning(row)]);

  @override
  Stream<CarePolicies> watchPolicies() => _db
      .watch(
        'SELECT * FROM care_policies ORDER BY updated_at, id',
        triggerOnTables: const {'care_policies'},
      )
      .map(_policies);

  @override
  Future<CareResult<CleaningEvent>> recordCleaning(
    GarmentId garment,
    CalendarDay day,
  ) => _guard(
    () => _db.writeTransaction((tx) async {
      if (day.isAfter(CalendarDay.of(_clock.nowUtc()))) {
        return const Err(InvalidCare(CareProblem.futureDay));
      }
      if (!await _garmentExists(tx, garment)) {
        return const Err(InvalidCare(CareProblem.unknownGarment));
      }
      final id = (await tx.get('SELECT uuid() AS id'))['id']! as String;
      final now = _clock.nowUtc();
      await tx.execute(
        'INSERT INTO cleaning_events (id, owner_id, garment_id, cleaned_on, '
        'created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)',
        [
          id,
          _ownerId,
          garment.value,
          day.iso,
          GarmentRow.iso(now),
          GarmentRow.iso(now),
        ],
      );
      await _operation(tx, id, 'record_cleaning', {
        'garment_id': garment.value,
        'cleaned_on': day.iso,
      });
      return Ok(
        CleaningEvent(
          id: id,
          garmentId: garment,
          cleanedOn: day,
          createdAt: now,
        ),
      );
    }),
  );

  @override
  Future<CareResult<void>> voidCleaning(String id) => _guard(
    () => _db.writeTransaction((tx) async {
      final row = await tx.getOptional(
        'SELECT voided_at FROM cleaning_events WHERE id = ?',
        [id],
      );
      if (row == null) return Err(CleaningNotFound(id));
      if (row['voided_at'] == null) {
        final now = GarmentRow.iso(_clock.nowUtc());
        await tx.execute(
          'UPDATE cleaning_events SET voided_at = ?, updated_at = ? '
          'WHERE id = ?',
          [now, now, id],
        );
        await _operation(tx, id, 'void_cleaning', const {});
      }
      return const Ok(null);
    }),
  );

  @override
  Future<CareResult<void>> setCategoryLaundry(GarmentCategory c, int? value) =>
      _setPolicy(
        PolicyScope.category,
        c.id,
        'laundry_after',
        value,
        CareLimits.maxLaundryAfter,
      );

  @override
  Future<CareResult<void>> setGarmentLaundry(GarmentId g, int? value) =>
      _setPolicy(
        PolicyScope.garment,
        g.value,
        'laundry_after',
        value,
        CareLimits.maxLaundryAfter,
      );

  @override
  Future<CareResult<void>> setCategoryRotation(GarmentCategory c, int? value) =>
      _setPolicy(
        PolicyScope.category,
        c.id,
        'rotation_days',
        value,
        CareLimits.maxRotationDays,
      );

  @override
  Future<CareResult<void>> setGarmentRotation(GarmentId g, int? value) =>
      _setPolicy(
        PolicyScope.garment,
        g.value,
        'rotation_days',
        value,
        CareLimits.maxRotationDays,
      );

  Future<CareResult<void>> _setPolicy(
    PolicyScope scope,
    String target,
    String column,
    int? value,
    int max,
  ) => _guard(
    () => _db.writeTransaction((tx) async {
      if (value != null && (value < 0 || value > max)) {
        return const Err(InvalidCare(CareProblem.outOfRange));
      }
      if (scope == PolicyScope.garment &&
          !await _garmentExists(tx, GarmentId(target))) {
        return const Err(InvalidCare(CareProblem.unknownGarment));
      }
      final id = policyId(_ownerId, scope, target);
      final now = GarmentRow.iso(_clock.nowUtc());
      final exists = await tx.getOptional(
        'SELECT 1 FROM care_policies WHERE id = ?',
        [id],
      );
      // `column` vem só das constantes acima.
      if (exists == null) {
        await tx.execute(
          'INSERT INTO care_policies (id, owner_id, scope, target, $column, '
          'updated_at) VALUES (?, ?, ?, ?, ?, ?)',
          [id, _ownerId, scope.id, target, value, now],
        );
      } else {
        await tx.execute(
          'UPDATE care_policies SET $column = ?, updated_at = ? WHERE id = ?',
          [value, now, id],
        );
      }
      await _operation(tx, id, 'set_policy', {
        'scope': scope.id,
        'target': target,
        column: value,
      });
      return const Ok(null);
    }),
  );

  static Future<bool> _garmentExists(
    SqliteReadContext tx,
    GarmentId id,
  ) async =>
      await tx.getOptional(
        'SELECT 1 FROM garments WHERE id = ? AND deleted_at IS NULL',
        [id.value],
      ) !=
      null;

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

  /// Para quem lê `cleaning_events` diretamente (ex.: backup).
  static CleaningEvent? cleaningFromRow(Map<String, Object?> row) =>
      _cleaning(row);

  static CleaningEvent? _cleaning(Map<String, Object?> row) {
    final day = CalendarDay.tryParse(row['cleaned_on'] as String?);
    final created = DateTime.tryParse(row['created_at'] as String? ?? '');
    final garment = row['garment_id'] as String?;
    if (day == null || created == null || garment == null) return null;
    return CleaningEvent(
      id: row['id']! as String,
      garmentId: GarmentId(garment),
      cleanedOn: day,
      createdAt: created,
    );
  }

  static CarePolicies _policies(List<Map<String, Object?>> rows) {
    final laundryCat = <GarmentCategory, int>{};
    final laundryGarment = <GarmentId, int>{};
    final rotationCat = <GarmentCategory, int>{};
    final rotationGarment = <GarmentId, int>{};
    // Ordenadas por updated_at: a mais recente ganha se houver repetidas.
    for (final row in rows) {
      final target = row['target'] as String?;
      if (target == null) continue;
      final laundry = row['laundry_after'] as int?;
      final rotation = row['rotation_days'] as int?;
      switch (PolicyScope.fromId(row['scope'] as String?)) {
        case PolicyScope.category:
          final c = GarmentCategory.fromId(target);
          if (c == null) continue;
          _put(laundryCat, c, laundry);
          _put(rotationCat, c, rotation);
        case PolicyScope.garment:
          _put(laundryGarment, GarmentId(target), laundry);
          _put(rotationGarment, GarmentId(target), rotation);
        case null:
          continue;
      }
    }
    return CarePolicies(
      laundryByCategory: laundryCat,
      laundryByGarment: laundryGarment,
      rotationByCategory: rotationCat,
      rotationByGarment: rotationGarment,
    );
  }

  static void _put<K>(Map<K, int> map, K key, int? value) {
    if (value == null) {
      map.remove(key);
    } else {
      map[key] = value;
    }
  }

  static Future<CareResult<T>> _guard<T>(
    Future<CareResult<T>> Function() action,
  ) async {
    try {
      return await action();
    } on SqliteException catch (e) {
      return Err(CareStorageFailure(e.message));
    }
  }
}
