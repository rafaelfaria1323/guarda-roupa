import 'dart:convert';
import 'dart:typed_data';

import 'package:powersync/powersync.dart';
import 'package:sqlite3/common.dart' show SqliteException;
import 'package:sqlite_async/sqlite_async.dart';

import '../../../core/domain/result.dart';
import '../../care/data/powersync_care_repository.dart';
import '../../care/domain/care_policies.dart';
import '../../outfits/data/powersync_outfit_repository.dart';
import '../../wardrobe/data/garment_row.dart';
import '../../wardrobe/data/powersync_wardrobe_repository.dart';
import '../../wear/data/powersync_wear_repository.dart';
import '../domain/backup.dart';
import 'backup_codec.dart';
import 'history_import.dart';
import 'restore_plan.dart';

sealed class RestoreProblem {
  const RestoreProblem();
}

/// O ficheiro não passou a verificação; nada foi alterado.
final class InvalidBackupFile extends RestoreProblem {
  const InvalidBackupFile(this.problem);
  final BackupProblem problem;
}

/// Com cloud, enquanto a primeira sincronização não termina não se sabe o
/// que a conta tem.
final class AccountNotSyncedYet extends RestoreProblem {
  const AccountNotSyncedYet();
}

/// A conta tem peças e não foi possível perguntar ao servidor o que foi
/// apagado depois do backup (sem rede): sem isso, o que apagaste podia
/// voltar sem dares por isso.
final class NeedsNetwork extends RestoreProblem {
  const NeedsNetwork();
}

final class RestoreFailed extends RestoreProblem {
  const RestoreFailed(this.detail);
  final String detail;
}

/// Pergunta ao servidor quais destes ids (da tabela [table]) esta conta
/// já apagou ou desfez. Falha sem rede.
typedef RemoteRemovedLookup = Future<Set<String>> Function(
  RemovableTable table,
  List<String> ids,
);

/// O que se vai fazer, para o preview: com e sem as peças apagadas depois
/// do backup.
final class RestorePreview {
  const RestorePreview._({
    required this.contents,
    required this.remoteRemoved,
    required this.accountEmpty,
    required this.withoutRemoved,
    required this.withRemoved,
  });

  final BackupContents contents;
  final RemovedIds remoteRemoved;

  /// Sem peças: por omissão recuperam-se também as apagadas (quem esvazia
  /// a conta para recuperar quer tudo de volta).
  final bool accountEmpty;
  final RestorePlan withoutRemoved;
  final RestorePlan withRemoved;

  RestorePlan plan({required bool restoreRemoved}) =>
      restoreRemoved ? withRemoved : withoutRemoved;
}

/// Recuperação de um backup, juntando ao que a conta tem (P-11,
/// docs/features/backups-e-recuperacao.md): [inspect] valida o ficheiro e
/// compara com a conta sem escrever nada (para o preview); [apply] volta a
/// comparar e escreve tudo numa transação.
final class BackupRestorer {
  BackupRestorer({
    required this._db,
    required this._ownerId,
    required this._accountSynced,
    this._remoteRemoved,
  });

  final PowerSyncDatabase _db;
  final String _ownerId;

  /// `true` sem cloud (dados só locais) ou depois da primeira sincronização.
  final bool _accountSynced;

  /// `null` sem cloud: tudo o que a conta apagou ainda está neste
  /// dispositivo.
  final RemoteRemovedLookup? _remoteRemoved;

  Future<Result<RestorePreview, RestoreProblem>> inspect(Uint8List zip) async {
    final decoded = BackupCodec.decode(zip);
    if (decoded case Err(:final failure)) {
      return Err(InvalidBackupFile(failure));
    }
    if (!_accountSynced) return const Err(AccountNotSyncedYet());
    final contents = (decoded as Ok<BackupContents, BackupProblem>).value;
    final account = await _db.readTransaction(_account);
    final empty = account.garments.isEmpty;
    final RemovedIds remote;
    try {
      remote = await _remote(contents);
    } on Object {
      if (!empty) return const Err(NeedsNetwork());
      return Ok(await _preview(contents, account, const {}, empty: true));
    }
    return Ok(await _preview(contents, account, remote, empty: empty));
  }

  Future<RestorePreview> _preview(
    BackupContents contents,
    AccountState account,
    RemovedIds remote, {
    required bool empty,
  }) async {
    final removed = _union(
      remote,
      await _db.readTransaction((tx) => _localRemoved(tx, contents)),
    );
    return RestorePreview._(
      contents: contents,
      remoteRemoved: remote,
      accountEmpty: empty,
      withoutRemoved: RestorePlan.build(
        contents,
        account,
        removed,
        restoreRemoved: false,
      ),
      withRemoved: RestorePlan.build(
        contents,
        account,
        removed,
        restoreRemoved: true,
      ),
    );
  }

  /// Devolve o que foi acrescentado.
  Future<Result<RestorePlan, RestoreProblem>> apply(
    RestorePreview preview, {
    required bool restoreRemoved,
  }) async {
    if (!_accountSynced) return const Err(AccountNotSyncedYet());
    final contents = preview.contents;
    try {
      final repo = PowerSyncWardrobeRepository(db: _db, ownerId: _ownerId);
      final plan = await _db.writeTransaction((tx) async {
        // De novo dentro da transação: a conta pode ter mudado desde o
        // preview.
        final plan = RestorePlan.build(
          contents,
          await _account(tx),
          _union(preview.remoteRemoved, await _localRemoved(tx, contents)),
          restoreRemoved: restoreRemoved,
        );
        final created = await repo.insertImported(
          tx,
          plan.newGarments,
          contents.photoFiles,
        );
        await HistoryImport.write(
          tx,
          ownerId: _ownerId,
          history: plan.history,
          newIds: {...plan.present, ...created},
          now: DateTime.now(),
          photoFiles: contents.photoFiles,
          knownInspirations: plan.knownInspirations,
        );
        return plan;
      });
      return Ok(plan);
    } on SqliteException catch (e) {
      return Err(RestoreFailed(e.message));
    } on StateError catch (e) {
      return Err(RestoreFailed(e.message));
    }
  }

  static Map<RemovableTable, List<String>> _ids(BackupContents contents) {
    final h = contents.history;
    return {
      RemovableTable.garments: [for (final g in contents.garments) g.id.value],
      RemovableTable.wears: [for (final w in h.wears) w.id],
      RemovableTable.cleanings: [for (final c in h.cleanings) c.id],
      RemovableTable.outfits: [for (final o in h.outfits) o.id],
      RemovableTable.inspirations: [for (final i in h.inspirations) i.id],
      RemovableTable.preferences: [for (final p in h.preferences) p.id],
    };
  }

  Future<RemovedIds> _remote(BackupContents contents) async {
    final lookup = _remoteRemoved;
    if (lookup == null) return const {};
    return {
      for (final MapEntry(:key, :value) in _ids(contents).entries)
        if (value.isNotEmpty) key: await lookup(key, value),
    };
  }

  static Future<RemovedIds> _localRemoved(
    SqliteReadContext tx,
    BackupContents contents,
  ) async => {
    for (final MapEntry(:key, :value) in _ids(contents).entries)
      if (value.isNotEmpty)
        key: {
          for (final row in await tx.getAll(
            'SELECT id FROM ${key.table} WHERE ${key.column} IS NOT NULL '
            'AND id IN (SELECT value FROM json_each(?))',
            [jsonEncode(value)],
          ))
            row['id']! as String,
        },
  };

  static RemovedIds _union(RemovedIds a, RemovedIds b) => {
    for (final t in RemovableTable.values) t: {...?a[t], ...?b[t]},
  };

  static Future<AccountState> _account(SqliteReadContext tx) async {
    Future<List<Map<String, Object?>>> rows(String sql) async => [
      for (final r in await tx.getAll(sql)) {...r},
    ];
    return AccountState(
      garments: [
        for (final r in await rows(
          'SELECT * FROM garments WHERE deleted_at IS NULL',
        ))
          ?GarmentRow.fromRow(r),
      ],
      wears: [
        for (final r in await rows(
          'SELECT * FROM wear_events WHERE voided_at IS NULL',
        ))
          ?PowerSyncWearRepository.fromRow(r),
      ],
      cleanings: [
        for (final r in await rows(
          'SELECT * FROM cleaning_events WHERE voided_at IS NULL',
        ))
          ?PowerSyncCareRepository.cleaningFromRow(r),
      ],
      outfits: [
        for (final r in await rows(
          'SELECT * FROM outfits WHERE deleted_at IS NULL',
        ))
          ?PowerSyncOutfitRepository.fromRow(r),
      ],
      policies: {
        for (final r in await rows('SELECT scope, target FROM care_policies'))
          if (PolicyScope.fromId(r['scope'] as String?) case final scope?)
            (scope, r['target']! as String),
      },
      inspirationIds: {
        for (final r in await rows(
          'SELECT id FROM inspirations WHERE deleted_at IS NULL',
        ))
          r['id']! as String,
      },
      preferenceIds: {
        for (final r in await rows(
          'SELECT id FROM style_preferences WHERE deleted_at IS NULL',
        ))
          r['id']! as String,
      },
    );
  }
}
