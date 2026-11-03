import 'dart:convert';

import 'package:powersync/powersync.dart';
import 'package:sqlite3/common.dart' show SqliteException;
import 'package:sqlite_async/sqlite_async.dart';

import '../../../core/domain/clock.dart';
import '../../../core/domain/result.dart';
import '../../wardrobe/data/garment_row.dart';
import '../../wardrobe/domain/garment.dart';
import '../../wardrobe/domain/garment_attributes.dart';
import '../domain/outfit.dart';
import '../domain/outfit_repository.dart';

/// Conjuntos sobre o SQLite do PowerSync: `outfits` é a visão otimista
/// local e `outfit_operations` a fila para `apply_outfit_operation`.
final class PowerSyncOutfitRepository implements OutfitRepository {
  PowerSyncOutfitRepository({
    required this._db,
    required this._ownerId,
    this._clock = const SystemClock(),
  });

  final PowerSyncDatabase _db;
  final String _ownerId;
  final Clock _clock;

  static const _tables = {'outfits'};

  @override
  Stream<List<Outfit>> watchOutfits() => _db
      .watch(
        'SELECT * FROM outfits WHERE deleted_at IS NULL '
        'ORDER BY updated_at DESC, id',
        triggerOnTables: _tables,
      )
      .map((rows) => [for (final row in rows) ?fromRow(row)]);

  @override
  Stream<Outfit?> watchOutfit(String id) => _db
      .watch(
        'SELECT * FROM outfits WHERE id = ? AND deleted_at IS NULL',
        parameters: [id],
        triggerOnTables: _tables,
      )
      .map((rows) => rows.isEmpty ? null : fromRow(rows.first));

  @override
  Future<OutfitResult<Outfit>> createOutfit(OutfitDraft draft) => _guard(
    () => _db.writeTransaction((tx) async {
      final draftProblem = await _validate(tx, draft, const {});
      if (draftProblem != null) return Err(draftProblem);
      final id = (await tx.get('SELECT uuid() AS id'))['id']! as String;
      final now = _clock.nowUtc();
      final outfit = Outfit(
        id: id,
        name: _name(draft.name),
        occasions: draft.occasions,
        items: draft.items,
        createdAt: now,
        updatedAt: now,
      );
      await tx.execute(
        'INSERT INTO outfits (id, owner_id, name, occasions, items, '
        'created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
        [
          id,
          _ownerId,
          outfit.name,
          jsonEncode(_occasionsJson(outfit.occasions)),
          jsonEncode(itemsJson(outfit.items)),
          GarmentRow.iso(now),
          GarmentRow.iso(now),
        ],
      );
      await _operation(tx, id, 'create_outfit', {
        'items': itemsJson(outfit.items),
        'name': ?outfit.name,
        'occasions': _occasionsJson(outfit.occasions),
      });
      return Ok(outfit);
    }),
  );

  @override
  Future<OutfitResult<Outfit>> updateOutfit(String id, OutfitDraft draft) =>
      _guard(
        () => _db.writeTransaction((tx) async {
          final row = await tx.getOptional(
            'SELECT * FROM outfits WHERE id = ? AND deleted_at IS NULL',
            [id],
          );
          final current = row == null ? null : fromRow(row);
          if (current == null) return Err(OutfitNotFound(id));
          final kept = {for (final i in current.items) i.garmentId};
          final draftProblem = await _validate(tx, draft, kept);
          if (draftProblem != null) return Err(draftProblem);

          // Só os campos que mudaram: o servidor junta campo a campo.
          final name = _name(draft.name);
          final changes = <String, Object?>{
            if (name != current.name) 'name': name,
            if (draft.occasions.length != current.occasions.length ||
                !draft.occasions.containsAll(current.occasions))
              'occasions': _occasionsJson(draft.occasions),
            if (!_sameItems(draft.items, current.items))
              'items': itemsJson(draft.items),
          };
          if (changes.isEmpty) return Ok(current);
          final now = _clock.nowUtc();
          await tx.execute(
            'UPDATE outfits SET name = ?, occasions = ?, items = ?, '
            'updated_at = ? WHERE id = ?',
            [
              name,
              jsonEncode(_occasionsJson(draft.occasions)),
              jsonEncode(itemsJson(draft.items)),
              GarmentRow.iso(now),
              id,
            ],
          );
          await _operation(tx, id, 'edit_outfit', changes);
          return Ok(
            Outfit(
              id: id,
              name: name,
              occasions: draft.occasions,
              items: draft.items,
              createdAt: current.createdAt,
              updatedAt: now,
            ),
          );
        }),
      );

  @override
  Future<OutfitResult<void>> deleteOutfit(String id) => _guard(
    () => _db.writeTransaction((tx) async {
      final row = await tx.getOptional(
        'SELECT deleted_at FROM outfits WHERE id = ?',
        [id],
      );
      if (row == null) return Err(OutfitNotFound(id));
      if (row['deleted_at'] == null) {
        final now = GarmentRow.iso(_clock.nowUtc());
        await tx.execute(
          'UPDATE outfits SET deleted_at = ?, updated_at = ? WHERE id = ?',
          [now, now, id],
        );
        await _operation(tx, id, 'delete_outfit', const {});
      }
      return const Ok(null);
    }),
  );

  /// Peças novas têm de estar ativas; as que já estavam ([kept]) podem
  /// entretanto ter sido arquivadas.
  Future<OutfitFailure?> _validate(
    SqliteReadContext tx,
    OutfitDraft draft,
    Set<GarmentId> kept,
  ) async {
    if (OutfitRules.validate(draft) case final problem?) {
      return InvalidOutfit(problem);
    }
    final ids = [for (final i in draft.items) i.garmentId.value];
    final rows = await tx.getAll(
      'SELECT id, archived_at FROM garments WHERE deleted_at IS NULL '
      'AND id IN (SELECT value FROM json_each(?))',
      [jsonEncode(ids)],
    );
    final usable = {
      for (final r in rows)
        if (r['archived_at'] == null ||
            kept.contains(GarmentId(r['id']! as String)))
          r['id']! as String,
    };
    return usable.length == ids.length ? null : const UnknownOutfitGarment();
  }

  Future<void> _operation(
    SqliteWriteContext tx,
    String outfitId,
    String kind,
    Map<String, Object?> data,
  ) => tx.execute(
    'INSERT INTO outfit_operations (id, outfit_id, kind, data, created_at) '
    'VALUES (uuid(), ?, ?, ?, ?)',
    [outfitId, kind, jsonEncode(data), GarmentRow.iso(_clock.nowUtc())],
  );

  static bool _sameItems(List<OutfitItem> a, List<OutfitItem> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static String? _name(String? name) {
    final trimmed = name?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  static List<String> _occasionsJson(Set<Occasion> occasions) => [
    for (final o in Occasion.values)
      if (occasions.contains(o)) o.id,
  ];

  static List<Map<String, String>> itemsJson(List<OutfitItem> items) => [
    for (final i in items) {'garment_id': i.garmentId.value, 'role': i.role.id},
  ];

  /// Linhas inválidas (ex.: de uma versão futura) ficam de fora; papéis e
  /// ocasiões desconhecidos são ignorados.
  static Outfit? fromRow(Map<String, Object?> row) {
    final created = DateTime.tryParse(row['created_at'] as String? ?? '');
    final updated = DateTime.tryParse(row['updated_at'] as String? ?? '');
    final rawItems = _decode(row['items']);
    if (created == null || updated == null || rawItems is! List) return null;
    final items = <OutfitItem>[
      for (final raw in rawItems)
        if (raw case {
          'garment_id': final String garment,
          'role': final String roleId,
        })
          if (OutfitRole.fromId(roleId) case final role?)
            OutfitItem(GarmentId(garment), role),
    ];
    if (items.isEmpty) return null;
    final occasions = switch (_decode(row['occasions'])) {
      final List<Object?> list => {
        for (final o in list)
          if (o is String && Occasion.fromId(o) != null) Occasion.fromId(o)!,
      },
      _ => <Occasion>{},
    };
    return Outfit(
      id: row['id']! as String,
      name: row['name'] as String?,
      occasions: occasions,
      items: items,
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

  static Future<OutfitResult<T>> _guard<T>(
    Future<OutfitResult<T>> Function() action,
  ) async {
    try {
      return await action();
    } on SqliteException catch (e) {
      return Err(OutfitStorageFailure(e.message));
    }
  }
}
