import 'dart:convert';

import 'package:powersync/powersync.dart';
import 'package:sqlite3/common.dart' show SqliteException;
import 'package:sqlite_async/sqlite_async.dart';

import '../../../core/domain/clock.dart';
import '../../../core/domain/result.dart';
import '../../outfits/data/powersync_outfit_repository.dart';
import '../../outfits/domain/outfit.dart';
import '../../wardrobe/data/garment_row.dart';
import '../../wardrobe/domain/garment.dart';
import '../../wardrobe/domain/garment_attributes.dart';
import '../../wear/domain/calendar_day.dart';
import '../domain/plan_entry.dart';
import '../domain/plan_repository.dart';

/// Plano semanal sobre o SQLite do PowerSync: `plan_entries` é a visão
/// otimista local e `plan_operations` a fila para `apply_plan_operation`.
///
/// A versão local sobe a cada edição, para que edições seguidas no mesmo
/// dispositivo assentem umas nas outras; a do servidor substitui-a depois.
final class PowerSyncPlanRepository implements PlanRepository {
  PowerSyncPlanRepository({
    required this._db,
    required this._ownerId,
    this._clock = const SystemClock(),
  });

  final PowerSyncDatabase _db;
  final String _ownerId;
  final Clock _clock;

  static const _tables = {'plan_entries'};

  @override
  Stream<List<PlanEntry>> watchDays(CalendarDay from, {int days = 7}) => _db
      .watch(
        'SELECT * FROM plan_entries WHERE deleted_at IS NULL '
        'AND day >= ? AND day <= ? ORDER BY day, id',
        parameters: [from.iso, from.addDays(days - 1).iso],
        triggerOnTables: _tables,
      )
      .map((rows) => [for (final row in rows) ?fromRow(row)]);

  @override
  Future<PlanResult<PlanEntry>> saveDay(
    CalendarDay day,
    PlanDraft draft,
  ) => _guard(
    () => _db.writeTransaction((tx) async {
      if (WeekPlanRules.validate(draft) case final problem?) {
        return Err(InvalidPlan(problem));
      }
      final row = await tx.getOptional(
        'SELECT * FROM plan_entries WHERE day = ? AND deleted_at IS NULL '
        'ORDER BY created_at, id LIMIT 1',
        [day.iso],
      );
      final current = row == null ? null : fromRow(row);
      final kept = {
        for (final i in current?.items ?? const <OutfitItem>[]) i.garmentId,
      };
      if (!await _garmentsUsable(tx, draft.items, kept)) {
        return const Err(UnknownPlanGarment());
      }
      final now = _clock.nowUtc();
      if (current == null) return Ok(await _create(tx, day, draft, now));

      final changes = <String, Object?>{
        if (draft.occasion != current.occasion) 'occasion': draft.occasion?.id,
        if (draft.tentative != current.tentative) 'tentative': draft.tentative,
        if (!_sameItems(draft.items, current.items))
          'items': PowerSyncOutfitRepository.itemsJson(draft.items),
        if (draft.status != current.status) 'status': draft.status.id,
      };
      if (changes.isEmpty) return Ok(current);
      await tx.execute(
        'UPDATE plan_entries SET occasion = ?, tentative = ?, items = ?, '
        'status = ?, version = ?, updated_at = ? WHERE id = ?',
        [
          draft.occasion?.id,
          draft.tentative ? 1 : 0,
          jsonEncode(PowerSyncOutfitRepository.itemsJson(draft.items)),
          draft.status.id,
          current.version + 1,
          GarmentRow.iso(now),
          current.id,
        ],
      );
      await _operation(tx, current.id, 'edit_plan_entry', {
        'base_version': current.version,
        ...changes,
      });
      return Ok(
        PlanEntry(
          id: current.id,
          day: day,
          occasion: draft.occasion,
          tentative: draft.tentative,
          items: draft.items,
          status: draft.status,
          version: current.version + 1,
          proposal: current.proposal,
          createdAt: current.createdAt,
          updatedAt: now,
        ),
      );
    }),
  );

  Future<PlanEntry> _create(
    SqliteWriteContext tx,
    CalendarDay day,
    PlanDraft draft,
    DateTime now,
  ) async {
    final id = (await tx.get('SELECT uuid() AS id'))['id']! as String;
    final items = PowerSyncOutfitRepository.itemsJson(draft.items);
    await tx.execute(
      'INSERT INTO plan_entries (id, owner_id, day, occasion, tentative, '
      'items, status, version, created_at, updated_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, 1, ?, ?)',
      [
        id,
        _ownerId,
        day.iso,
        draft.occasion?.id,
        draft.tentative ? 1 : 0,
        jsonEncode(items),
        draft.status.id,
        GarmentRow.iso(now),
        GarmentRow.iso(now),
      ],
    );
    await _operation(tx, id, 'create_plan_entry', {
      'day': day.iso,
      'occasion': draft.occasion?.id,
      'tentative': draft.tentative,
      'items': items,
      'status': draft.status.id,
    });
    return PlanEntry(
      id: id,
      day: day,
      occasion: draft.occasion,
      tentative: draft.tentative,
      items: draft.items,
      status: draft.status,
      version: 1,
      createdAt: now,
      updatedAt: now,
    );
  }

  @override
  Future<PlanResult<void>> resolveProposal(String id, {required bool accept}) =>
      _guard(
        () => _db.writeTransaction((tx) async {
          final row = await tx.getOptional(
            'SELECT * FROM plan_entries WHERE id = ? AND deleted_at IS NULL',
            [id],
          );
          final current = row == null ? null : fromRow(row);
          if (current == null) return Err(PlanEntryNotFound(id));
          final proposal = current.proposal;
          if (proposal == null) return const Ok(null);
          final now = GarmentRow.iso(_clock.nowUtc());
          if (accept) {
            final items = proposal.items ?? current.items;
            await tx.execute(
              'UPDATE plan_entries SET occasion = ?, tentative = ?, items = ?, '
              'status = ?, proposal = NULL, version = ?, updated_at = ? '
              'WHERE id = ?',
              [
                (proposal.changesOccasion
                        ? proposal.occasion
                        : current.occasion)
                    ?.id,
                (proposal.tentative ?? current.tentative) ? 1 : 0,
                jsonEncode(PowerSyncOutfitRepository.itemsJson(items)),
                (proposal.status ?? current.status).id,
                current.version + 1,
                now,
                id,
              ],
            );
          } else {
            await tx.execute(
              'UPDATE plan_entries SET proposal = NULL, updated_at = ? '
              'WHERE id = ?',
              [now, id],
            );
          }
          await _operation(tx, id, 'resolve_plan_proposal', {'accept': accept});
          return const Ok(null);
        }),
      );

  @override
  Future<PlanResult<void>> deleteEntry(String id) => _guard(
    () => _db.writeTransaction((tx) async {
      final row = await tx.getOptional(
        'SELECT deleted_at FROM plan_entries WHERE id = ?',
        [id],
      );
      if (row == null) return Err(PlanEntryNotFound(id));
      if (row['deleted_at'] == null) {
        final now = GarmentRow.iso(_clock.nowUtc());
        await tx.execute(
          'UPDATE plan_entries SET deleted_at = ?, updated_at = ? WHERE id = ?',
          [now, now, id],
        );
        await _operation(tx, id, 'delete_plan_entry', const {});
      }
      return const Ok(null);
    }),
  );

  /// Peças novas têm de estar ativas; as que já estavam ([kept]) podem
  /// entretanto ter sido arquivadas.
  static Future<bool> _garmentsUsable(
    SqliteReadContext tx,
    List<OutfitItem> items,
    Set<GarmentId> kept,
  ) async {
    if (items.isEmpty) return true;
    final ids = [for (final i in items) i.garmentId.value];
    final rows = await tx.getAll(
      'SELECT id, archived_at FROM garments WHERE deleted_at IS NULL '
      'AND id IN (SELECT value FROM json_each(?))',
      [jsonEncode(ids)],
    );
    final usable = [
      for (final r in rows)
        if (r['archived_at'] == null ||
            kept.contains(GarmentId(r['id']! as String)))
          r,
    ];
    return usable.length == ids.length;
  }

  Future<void> _operation(
    SqliteWriteContext tx,
    String entryId,
    String kind,
    Map<String, Object?> data,
  ) => tx.execute(
    'INSERT INTO plan_operations (id, entry_id, kind, data, created_at) '
    'VALUES (uuid(), ?, ?, ?, ?)',
    [entryId, kind, jsonEncode(data), GarmentRow.iso(_clock.nowUtc())],
  );

  static bool _sameItems(List<OutfitItem> a, List<OutfitItem> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Linhas inválidas (ex.: de uma versão futura) ficam de fora; papéis
  /// desconhecidos são ignorados.
  static PlanEntry? fromRow(Map<String, Object?> row) {
    final day = CalendarDay.tryParse(row['day'] as String?);
    final created = DateTime.tryParse(row['created_at'] as String? ?? '');
    final updated = DateTime.tryParse(row['updated_at'] as String? ?? '');
    final status = PlanStatus.fromId(row['status'] as String?);
    final items = _items(_decode(row['items']));
    final version = row['version'];
    if (day == null ||
        created == null ||
        updated == null ||
        status == null ||
        items == null ||
        version is! int) {
      return null;
    }
    return PlanEntry(
      id: row['id']! as String,
      day: day,
      occasion: Occasion.fromId(row['occasion'] as String?),
      tentative: _bool(row['tentative']) ?? false,
      items: items,
      status: status,
      version: version,
      proposal: _proposal(_decode(row['proposal'])),
      createdAt: created,
      updatedAt: updated,
    );
  }

  static PlanProposal? _proposal(Object? raw) {
    if (raw is! Map<String, Object?> || raw.isEmpty) return null;
    return PlanProposal(
      changesOccasion: raw.containsKey('occasion'),
      occasion: Occasion.fromId(raw['occasion'] as String?),
      tentative: _bool(raw['tentative']),
      items: raw.containsKey('items') ? _items(raw['items']) : null,
      status: PlanStatus.fromId(raw['status'] as String?),
    );
  }

  static List<OutfitItem>? _items(Object? raw) => raw is! List
      ? null
      : [
          for (final item in raw)
            if (item case {
              'garment_id': final String garment,
              'role': final String roleId,
            })
              if (OutfitRole.fromId(roleId) case final role?)
                OutfitItem(GarmentId(garment), role),
        ];

  /// O PowerSync guarda booleanos do Postgres como texto ou inteiro.
  static bool? _bool(Object? v) => switch (v) {
    final bool b => b,
    final int i => i != 0,
    'true' || '1' => true,
    'false' || '0' => false,
    _ => null,
  };

  static Object? _decode(Object? text) {
    if (text is! String) return null;
    try {
      return jsonDecode(text);
    } on FormatException {
      return null;
    }
  }

  static Future<PlanResult<T>> _guard<T>(
    Future<PlanResult<T>> Function() action,
  ) async {
    try {
      return await action();
    } on SqliteException catch (e) {
      return Err(PlanStorageFailure(e.message));
    }
  }
}
