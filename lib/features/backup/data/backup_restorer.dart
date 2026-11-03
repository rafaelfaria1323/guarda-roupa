import 'dart:typed_data';

import 'package:powersync/powersync.dart';
import 'package:sqlite3/common.dart' show SqliteException;

import '../../../core/domain/result.dart';
import '../../wardrobe/data/powersync_wardrobe_repository.dart';
import '../domain/backup.dart';
import 'backup_codec.dart';

sealed class RestoreProblem {
  const RestoreProblem();
}

/// O ficheiro não passou a verificação; nada foi alterado.
final class InvalidBackupFile extends RestoreProblem {
  const InvalidBackupFile(this.problem);
  final BackupProblem problem;
}

/// Primeiro modo de recuperação (até P-11): só para uma conta sem peças.
final class AccountNotEmpty extends RestoreProblem {
  const AccountNotEmpty();
}

/// Com cloud, enquanto a primeira sincronização não termina não se sabe se a
/// conta está vazia.
final class AccountNotSyncedYet extends RestoreProblem {
  const AccountNotSyncedYet();
}

final class RestoreFailed extends RestoreProblem {
  const RestoreFailed(this.detail);
  final String detail;
}

/// Recuperação para um destino vazio (docs/features/backups-e-recuperacao.md):
/// [inspect] valida o ficheiro e o destino sem escrever nada (para o
/// preview); [apply] escreve tudo numa transação.
final class BackupRestorer {
  BackupRestorer({
    required this._db,
    required this._ownerId,
    required this._accountSynced,
  });

  final PowerSyncDatabase _db;
  final String _ownerId;

  /// `true` sem cloud (dados só locais) ou depois da primeira sincronização.
  final bool _accountSynced;

  Future<Result<BackupContents, RestoreProblem>> inspect(Uint8List zip) async {
    final decoded = BackupCodec.decode(zip);
    if (decoded case Err(:final failure)) {
      return Err(InvalidBackupFile(failure));
    }
    if (await _destinationProblem() case final problem?) return Err(problem);
    return Ok((decoded as Ok<BackupContents, BackupProblem>).value);
  }

  Future<Result<int, RestoreProblem>> apply(BackupContents contents) async {
    if (await _destinationProblem() case final problem?) return Err(problem);
    try {
      final repo = PowerSyncWardrobeRepository(db: _db, ownerId: _ownerId);
      final done = await repo.importGarments(
        contents.garments,
        contents.photoFiles,
      );
      return done ? Ok(contents.garments.length) : const Err(AccountNotEmpty());
    } on SqliteException catch (e) {
      return Err(RestoreFailed(e.message));
    } on StateError catch (e) {
      return Err(RestoreFailed(e.message));
    }
  }

  Future<RestoreProblem?> _destinationProblem() async {
    if (!_accountSynced) return const AccountNotSyncedYet();
    final row = await _db.get(
      'SELECT count(*) AS n FROM garments WHERE deleted_at IS NULL',
    );
    return row['n'] == 0 ? null : const AccountNotEmpty();
  }
}
