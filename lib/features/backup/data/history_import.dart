import 'dart:convert';

import 'package:sqlite_async/sqlite_async.dart';

import '../../care/data/powersync_care_repository.dart';
import '../../care/domain/care_policies.dart';
import '../../outfits/data/powersync_outfit_repository.dart';
import '../../wardrobe/data/garment_row.dart';
import '../../outfits/domain/outfit.dart';
import '../../wardrobe/domain/garment.dart';
import '../../wardrobe/domain/garment_attributes.dart';
import '../domain/backup.dart';

/// Recupera o histórico de um backup para as peças acabadas de importar
/// (ids novos em [newIds]), dentro da transação da recuperação.
///
/// Utilizações e limpezas ficam com ids novos e seguem pela fila normal
/// (`record_wear`, `record_cleaning`, `set_policy`), pela ordem em que
/// foram registadas: assim o servidor mantém a ordem entre uma utilização
/// e uma limpeza do mesmo dia. Só corre num destino vazio, por isso não
/// duplica utilizações de uma conta existente. Os conjuntos também ficam
/// com ids novos (`create_outfit`).
abstract final class HistoryImport {
  static Future<void> write(
    SqliteWriteContext tx, {
    required String ownerId,
    required BackupHistory history,
    required Map<GarmentId, GarmentId> newIds,
    required DateTime now,
  }) async {
    final stamp = GarmentRow.iso(now.toUtc());

    String mapped(GarmentId old) {
      final id = newIds[old];
      if (id == null) throw StateError('Peça sem correspondência: $old');
      return id.value;
    }

    Future<String> newId() async =>
        (await tx.get('SELECT uuid() AS id'))['id']! as String;

    Future<void> operation(
      String eventId,
      String kind,
      Map<String, Object?> data,
    ) => tx.execute(
      'INSERT INTO wear_operations (id, event_id, kind, data, created_at) '
      'VALUES (uuid(), ?, ?, ?, ?)',
      [eventId, kind, jsonEncode(data), stamp],
    );

    final events = <(DateTime, Future<void> Function())>[
      for (final w in history.wears)
        (
          w.createdAt,
          () async {
            final id = await newId();
            final ids = [for (final g in w.garmentIds) mapped(g)];
            await tx.execute(
              'INSERT INTO wear_events (id, owner_id, worn_on, garment_ids, '
              'created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)',
              [
                id,
                ownerId,
                w.wornOn.iso,
                jsonEncode(ids),
                GarmentRow.iso(w.createdAt),
                stamp,
              ],
            );
            await operation(id, 'record_wear', {
              'worn_on': w.wornOn.iso,
              'garment_ids': ids,
            });
          },
        ),
      for (final c in history.cleanings)
        (
          c.createdAt,
          () async {
            final id = await newId();
            final garment = mapped(c.garmentId);
            await tx.execute(
              'INSERT INTO cleaning_events (id, owner_id, garment_id, '
              'cleaned_on, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)',
              [
                id,
                ownerId,
                garment,
                c.cleanedOn.iso,
                GarmentRow.iso(c.createdAt),
                stamp,
              ],
            );
            await operation(id, 'record_cleaning', {
              'garment_id': garment,
              'cleaned_on': c.cleanedOn.iso,
            });
          },
        ),
    ];
    // Ordenação estável: empates mantêm utilizações antes de limpezas, como
    // no ficheiro.
    final ordered = [for (final (i, e) in events.indexed) (i, e)]
      ..sort((a, b) {
        final byTime = a.$2.$1.compareTo(b.$2.$1);
        return byTime != 0 ? byTime : a.$1.compareTo(b.$1);
      });
    for (final (_, (_, write)) in ordered) {
      await write();
    }

    for (final p in history.policies) {
      final target = switch (p.scope) {
        PolicyScope.category => p.target,
        PolicyScope.garment => mapped(GarmentId(p.target)),
      };
      final id = PowerSyncCareRepository.policyId(ownerId, p.scope, target);
      final exists = await tx.getOptional(
        'SELECT 1 FROM care_policies WHERE id = ?',
        [id],
      );
      if (exists == null) {
        await tx.execute(
          'INSERT INTO care_policies (id, owner_id, scope, target, '
          'laundry_after, rotation_days, updated_at) '
          'VALUES (?, ?, ?, ?, ?, ?, ?)',
          [
            id,
            ownerId,
            p.scope.id,
            target,
            p.laundryAfter,
            p.rotationDays,
            stamp,
          ],
        );
      } else {
        await tx.execute(
          'UPDATE care_policies SET laundry_after = ?, rotation_days = ?, '
          'updated_at = ? WHERE id = ?',
          [p.laundryAfter, p.rotationDays, stamp, id],
        );
      }
      // Os dois campos, para ficar igual ao backup (null = predefinido).
      await operation(id, 'set_policy', {
        'scope': p.scope.id,
        'target': target,
        'laundry_after': p.laundryAfter,
        'rotation_days': p.rotationDays,
      });
    }

    for (final o in history.outfits) {
      final id = await newId();
      final items = PowerSyncOutfitRepository.itemsJson([
        for (final i in o.items)
          OutfitItem(GarmentId(mapped(i.garmentId)), i.role),
      ]);
      final occasions = [
        for (final occasion in Occasion.values)
          if (o.occasions.contains(occasion)) occasion.id,
      ];
      await tx.execute(
        'INSERT INTO outfits (id, owner_id, name, occasions, items, '
        'created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
        [
          id,
          ownerId,
          o.name,
          jsonEncode(occasions),
          jsonEncode(items),
          GarmentRow.iso(o.createdAt),
          stamp,
        ],
      );
      await tx.execute(
        'INSERT INTO outfit_operations (id, outfit_id, kind, data, created_at) '
        'VALUES (uuid(), ?, ?, ?, ?)',
        [
          id,
          'create_outfit',
          jsonEncode({'items': items, 'name': ?o.name, 'occasions': occasions}),
          stamp,
        ],
      );
    }
  }
}
