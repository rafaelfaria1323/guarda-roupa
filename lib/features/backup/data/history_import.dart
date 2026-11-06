import 'dart:convert';
import 'dart:typed_data';

import 'package:sqlite_async/sqlite_async.dart';

import '../../care/data/powersync_care_repository.dart';
import '../../care/domain/care_policies.dart';
import '../../inspirations/data/powersync_inspiration_repository.dart';
import '../../inspirations/data/powersync_preference_repository.dart';
import '../../inspirations/domain/style_preference.dart';
import '../../outfits/data/powersync_outfit_repository.dart';
import '../../wardrobe/data/garment_row.dart';
import '../../wardrobe/data/photo_files.dart';
import '../../wardrobe/domain/garment_photo.dart';
import '../../outfits/domain/outfit.dart';
import '../../wardrobe/domain/garment.dart';
import '../../wardrobe/domain/garment_attributes.dart';
import '../domain/backup.dart';

/// Recupera o histórico de um backup para as peças da conta ([newIds]: o id
/// de cada peça do backup na conta, nova ou que já lá estava), dentro da
/// transação da recuperação. O [history] já vem filtrado pelo
/// `RestorePlan`: sem o que a conta já tem nem o que foi desfeito ou
/// apagado depois do backup.
///
/// Utilizações e limpezas ficam com ids novos e seguem pela fila normal
/// (`record_wear`, `record_cleaning`, `set_policy`), pela ordem em que
/// foram registadas: assim o servidor mantém a ordem entre uma utilização
/// e uma limpeza do mesmo dia. Um valor de lavagem/rotatividade que a
/// conta já tem fica como está. Os conjuntos também ficam
/// com ids novos (`create_outfit`), tal como as inspirações e preferências
/// (`create_inspiration`, `create_preference`). Estas podem já existir sem
/// peças: uma inspiração igual ou uma preferência com o mesmo alvo não se
/// repete. A imagem de uma inspiração nova ganha id novo, fica neste
/// dispositivo e segue como `set_inspiration_image` (os ficheiros sobem
/// primeiro); uma inspiração reutilizada fica com a imagem que já tinha.
abstract final class HistoryImport {
  static Future<void> write(
    SqliteWriteContext tx, {
    required String ownerId,
    required BackupHistory history,
    required Map<GarmentId, GarmentId> newIds,
    required DateTime now,
    Map<(String, PhotoVariant), Uint8List> photoFiles = const {},
    Map<String, String> knownInspirations = const {},
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
      // O que a conta já tem fica como está.
      if (exists != null) continue;
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

    await _style(
      tx,
      ownerId: ownerId,
      history: history,
      stamp: stamp!,
      photoFiles: photoFiles,
      knownInspirations: knownInspirations,
    );
  }

  static Future<void> _style(
    SqliteWriteContext tx, {
    required String ownerId,
    required BackupHistory history,
    required String stamp,
    required Map<(String, PhotoVariant), Uint8List> photoFiles,
    required Map<String, String> knownInspirations,
  }) async {
    Future<void> operation(
      String entityId,
      String kind,
      Map<String, Object?> data,
    ) => tx.execute(
      'INSERT INTO style_operations (id, entity_id, kind, data, created_at) '
      'VALUES (uuid(), ?, ?, ?, ?)',
      [entityId, kind, jsonEncode(data), stamp],
    );

    // Inspirações: as iguais às que já existem reutilizam-se.
    final existing = <String, String>{
      for (final row in await tx.getAll(
        'SELECT * FROM inspirations WHERE deleted_at IS NULL',
      ))
        if (PowerSyncInspirationRepository.fromRow(row) case final i?)
          jsonEncode(PowerSyncInspirationRepository.columns(i.toDraft())): i.id,
    };
    final inspirationIds = {...knownInspirations};
    for (final i in history.inspirations) {
      final fields = PowerSyncInspirationRepository.columns(i.toDraft());
      final key = jsonEncode(fields);
      if (existing[key] case final id?) {
        inspirationIds[i.id] = id;
        continue;
      }
      final id = (await tx.get('SELECT uuid() AS id'))['id']! as String;
      await tx.execute(
        'INSERT INTO inspirations (id, owner_id, ${fields.keys.join(', ')}, '
        'created_at, updated_at) VALUES (?, ?, '
        '${List.filled(fields.length, '?').join(', ')}, ?, ?)',
        [
          id,
          ownerId,
          for (final v in fields.values) v is List ? jsonEncode(v) : v,
          GarmentRow.iso(i.createdAt),
          stamp,
        ],
      );
      await operation(id, 'create_inspiration', {
        for (final MapEntry(:key, :value) in fields.entries)
          if (value != null && !(value is List && value.isEmpty)) key: value,
      });
      if (i.image case final image?) {
        final added = GarmentPhoto(
          id: (await tx.get('SELECT uuid() AS id'))['id']! as String,
          width: image.width,
          height: image.height,
          bytes: image.bytes,
          thumbBytes: image.thumbBytes,
          sha256: image.sha256,
        );
        for (final variant in PhotoVariant.values) {
          final bytes = photoFiles[(image.id, variant)];
          if (bytes == null) throw StateError('Imagem em falta: ${image.id}');
          await PhotoFiles.put(tx, added.id, variant, bytes);
        }
        final json = GarmentRow.photoJson(added);
        await tx.execute('UPDATE inspirations SET image = ? WHERE id = ?', [
          jsonEncode(json),
          id,
        ]);
        await operation(id, 'set_inspiration_image', {'image': json});
      }
      existing[key] = id;
      inspirationIds[i.id] = id;
    }

    // Preferências: uma por alvo (assunto, valor e contexto).
    final targets = [
      for (final row in await tx.getAll(
        'SELECT * FROM style_preferences WHERE deleted_at IS NULL',
      ))
        if (PowerSyncPreferenceRepository.fromRow(row) case final p?)
          p.toDraft(),
    ];
    for (final p in history.preferences) {
      final draft = PreferenceDraft(
        subject: p.subject,
        value: p.value,
        stance: p.stance,
        occasions: p.occasions,
        inspirationId: inspirationIds[p.inspirationId],
      );
      if (targets.any(draft.sameTarget)) continue;
      final id = (await tx.get('SELECT uuid() AS id'))['id']! as String;
      final occasions = [
        for (final o in Occasion.values)
          if (p.occasions.contains(o)) o.id,
      ];
      await tx.execute(
        'INSERT INTO style_preferences (id, owner_id, subject, value, stance, '
        'occasions, inspiration_id, created_at, updated_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          id,
          ownerId,
          draft.subject.id,
          draft.value,
          draft.stance.id,
          jsonEncode(occasions),
          draft.inspirationId,
          GarmentRow.iso(p.createdAt),
          stamp,
        ],
      );
      await operation(id, 'create_preference', {
        'subject': draft.subject.id,
        'value': draft.value,
        'stance': draft.stance.id,
        if (occasions.isNotEmpty) 'occasions': occasions,
        'inspiration_id': ?draft.inspirationId,
      });
      targets.add(draft);
    }
  }
}
