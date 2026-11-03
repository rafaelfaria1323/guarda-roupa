import 'dart:convert';

import 'package:powersync/powersync.dart';
import 'package:sqlite3/common.dart' show SqliteException;
import 'package:sqlite_async/sqlite_async.dart';

import '../../../core/domain/result.dart';
import '../domain/availability.dart';
import '../domain/garment.dart';
import '../domain/garment_factory.dart';
import '../domain/garment_filter.dart';
import '../domain/wardrobe_repository.dart';
import 'garment_row.dart';

/// Implementação local-first sobre o SQLite do PowerSync.
///
/// Cada mutação atualiza `garments` (visão otimista) e regista a operação de
/// domínio em `garment_operations` **na mesma transação**. O envio para o
/// servidor é feito pelo conector (ver `OperationUploadQueue`).
final class PowerSyncWardrobeRepository implements WardrobeRepository {
  PowerSyncWardrobeRepository({
    required this._db,
    required this._ownerId,
    this._factory = const GarmentFactory(),
  });

  final PowerSyncDatabase _db;
  final String _ownerId;
  final GarmentFactory _factory;

  static const _select =
      'SELECT * FROM garments WHERE deleted_at IS NULL '
      'ORDER BY created_at DESC, id';

  @override
  Stream<List<Garment>> watchGarments(GarmentFilter filter) => _db
      .watch(_select, triggerOnTables: const {'garments'})
      .map(
        (rows) => [
          for (final row in rows)
            if (GarmentRow.fromRow(row) case final g? when filter.matches(g)) g,
        ],
      );

  @override
  Stream<Garment?> watchGarment(GarmentId id) => _db
      .watch(
        'SELECT * FROM garments WHERE id = ? AND deleted_at IS NULL',
        parameters: [id.value],
        triggerOnTables: const {'garments'},
      )
      .map((rows) => rows.isEmpty ? null : GarmentRow.fromRow(rows.first));

  @override
  Future<WardrobeResult<Garment>> addGarment(GarmentDraft draft) async {
    final created = _factory.create(draft);
    if (created case Err(:final failure)) return Err(InvalidDraft(failure));
    final garment = (created as Ok<Garment, List<DraftProblem>>).value;

    return _guard(() async {
      await _db.writeTransaction((tx) async {
        await tx.execute(
          'INSERT INTO garments (id, owner_id, category, name, brand, notes, '
          'colors, availability, archived_at, created_at, updated_at, version) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?, NULL, ?, ?, 0)',
          [
            garment.id.value,
            _ownerId,
            garment.category.id,
            garment.name,
            garment.brand,
            garment.notes,
            GarmentRow.encodeColors(garment.colors),
            garment.availability.id,
            GarmentRow.iso(garment.createdAt),
            GarmentRow.iso(garment.updatedAt),
          ],
        );
        await _recordOperation(tx, garment.id, 'create', {
          'category': garment.category.id,
          'name': garment.name,
          'brand': garment.brand,
          'notes': garment.notes,
          'colors': GarmentRow.colorsJson(garment.colors),
          'created_at': GarmentRow.iso(garment.createdAt),
        });
      });
      return Ok(garment);
    });
  }

  @override
  Future<WardrobeResult<Garment>> updateGarment(
    GarmentId id,
    GarmentDraft draft,
  ) => _mutate(id, (tx, current) async {
    final edited = _factory.edit(current, draft);
    if (edited case Err(:final failure)) return Err(InvalidDraft(failure));
    final next = (edited as Ok<Garment, List<DraftProblem>>).value;

    final changes = <String, Object?>{
      if (current.category != next.category)
        'category': {'from': current.category.id, 'to': next.category.id},
      if (current.name != next.name)
        'name': {'from': current.name, 'to': next.name},
      if (current.brand != next.brand)
        'brand': {'from': current.brand, 'to': next.brand},
      if (current.notes != next.notes)
        'notes': {'from': current.notes, 'to': next.notes},
      if (!_sameColors(current, next))
        'colors': {
          'from': GarmentRow.colorsJson(current.colors),
          'to': GarmentRow.colorsJson(next.colors),
        },
    };
    if (changes.isEmpty) return Ok(current);

    await tx.execute(
      'UPDATE garments SET category = ?, name = ?, brand = ?, notes = ?, '
      'colors = ?, updated_at = ? WHERE id = ?',
      [
        next.category.id,
        next.name,
        next.brand,
        next.notes,
        GarmentRow.encodeColors(next.colors),
        GarmentRow.iso(next.updatedAt),
        id.value,
      ],
    );
    await _recordOperation(tx, id, 'edit', {'changes': changes});
    return Ok(next);
  });

  @override
  Future<WardrobeResult<Garment>> duplicateGarment(GarmentId source) async {
    final current = await _find(_db, source);
    if (current == null) return Err(GarmentNotFound(source));
    return addGarment(GarmentDraft.duplicateOf(current));
  }

  @override
  Future<WardrobeResult<Garment>> setAvailability(
    GarmentId id,
    Availability availability,
  ) => _mutate(id, (tx, current) async {
    if (current.availability == availability) return Ok(current);
    final next = _factory.withAvailability(current, availability);
    await tx.execute(
      'UPDATE garments SET availability = ?, updated_at = ? WHERE id = ?',
      [availability.id, GarmentRow.iso(next.updatedAt), id.value],
    );
    await _recordOperation(tx, id, 'set_availability', {
      'from': current.availability.id,
      'to': availability.id,
    });
    return Ok(next);
  });

  @override
  Future<WardrobeResult<Garment>> archiveGarment(GarmentId id) =>
      _mutate(id, (tx, current) async {
        if (current.isArchived) return Ok(current);
        final next = _factory.archive(current);
        await tx.execute(
          'UPDATE garments SET archived_at = ?, updated_at = ? WHERE id = ?',
          [
            GarmentRow.iso(next.archivedAt),
            GarmentRow.iso(next.updatedAt),
            id.value,
          ],
        );
        await _recordOperation(tx, id, 'archive', {
          // O servidor guarda este valor, para o desarquivar seguinte (que o
          // envia como base) coincidir mesmo sem sincronizar entre os dois.
          'archived_at': GarmentRow.iso(next.archivedAt),
        });
        return Ok(next);
      });

  @override
  Future<WardrobeResult<Garment>> unarchiveGarment(GarmentId id) =>
      _mutate(id, (tx, current) async {
        if (!current.isArchived) return Ok(current);
        final next = _factory.unarchive(current);
        await tx.execute(
          'UPDATE garments SET archived_at = NULL, updated_at = ? WHERE id = ?',
          [GarmentRow.iso(next.updatedAt), id.value],
        );
        await _recordOperation(tx, id, 'unarchive', {
          'archived_at': GarmentRow.iso(current.archivedAt),
        });
        return Ok(next);
      });

  Future<WardrobeResult<Garment>> _mutate(
    GarmentId id,
    Future<WardrobeResult<Garment>> Function(
      SqliteWriteContext tx,
      Garment current,
    )
    change,
  ) => _guard(
    () => _db.writeTransaction((tx) async {
      final current = await _find(tx, id);
      if (current == null) return Err(GarmentNotFound(id));
      return change(tx, current);
    }),
  );

  Future<Garment?> _find(SqliteReadContext ctx, GarmentId id) async {
    final row = await ctx.getOptional(
      'SELECT * FROM garments WHERE id = ? AND deleted_at IS NULL',
      [id.value],
    );
    return row == null ? null : GarmentRow.fromRow(row);
  }

  Future<void> _recordOperation(
    SqliteWriteContext tx,
    GarmentId garmentId,
    String kind,
    Map<String, Object?> data,
  ) => tx.execute(
    'INSERT INTO garment_operations (id, garment_id, kind, data, created_at) '
    'VALUES (uuid(), ?, ?, ?, ?)',
    [garmentId.value, kind, jsonEncode(data), GarmentRow.iso(DateTime.now())],
  );

  static bool _sameColors(Garment a, Garment b) {
    if (a.colors.length != b.colors.length) return false;
    for (var i = 0; i < a.colors.length; i++) {
      if (a.colors[i] != b.colors[i]) return false;
    }
    return true;
  }

  /// Converte falhas do SQLite em `StorageFailure`, sem esconder o erro.
  static Future<WardrobeResult<Garment>> _guard(
    Future<WardrobeResult<Garment>> Function() action,
  ) async {
    try {
      return await action();
    } on SqliteException catch (e) {
      return Err(StorageFailure(e.message));
    }
  }
}
