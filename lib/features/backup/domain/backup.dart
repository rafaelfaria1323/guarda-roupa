import 'dart:typed_data';

import '../../care/domain/care_policies.dart';
import '../../care/domain/cleaning_event.dart';
import '../../wardrobe/domain/garment.dart';
import '../../wardrobe/domain/garment_photo.dart';
import '../../wear/domain/wear_event.dart';

/// Formato do ficheiro de backup (docs/features/backups-e-recuperacao.md).
///
/// ZIP com `manifest.json` (formato, versão, data, contagens e a lista de
/// ficheiros com tamanho e SHA-256), `data/garments.json`,
/// `data/history.json` (desde a v2: utilizações, limpezas e valores de
/// lavagem/rotatividade) e as fotografias em `photos/{id}/main.jpg|thumb.jpg`.
/// Sem tokens, chaves ou URLs.
abstract final class BackupFormat {
  static const name = 'guarda-roupa-backup';

  /// Sobe quando o leitor antigo deixar de perceber o conteúdo.
  /// v1: peças e fotografias. v2: + `data/history.json`.
  static const version = 2;

  static const manifestPath = 'manifest.json';
  static const garmentsPath = 'data/garments.json';
  static const historyPath = 'data/history.json';

  static String photoPath(String photoId, PhotoVariant variant) =>
      'photos/$photoId/${variant.id}.jpg';

  /// Limites de leitura, contra ficheiros corrompidos ou maliciosos.
  static const maxFiles = 20000;
  static const maxFileBytes = 32 * 1024 * 1024;
  static const maxTotalBytes = 2 * 1024 * 1024 * 1024;
}

/// O que um backup contém, para mostrar antes de qualquer recuperação.
final class BackupSummary {
  const BackupSummary({
    required this.exportedAt,
    required this.garments,
    required this.photos,
    required this.pendingOperations,
    this.wears = 0,
    this.cleanings = 0,
  });

  final DateTime exportedAt;
  final int garments;
  final int photos;
  final int wears;
  final int cleanings;

  /// Alterações ainda por sincronizar no momento da exportação (estão
  /// incluídas no backup, mas não tinham chegado à cloud).
  final int pendingOperations;
}

final class BackupContents {
  const BackupContents({
    required this.summary,
    required this.garments,
    required this.photoFiles,
    this.history = BackupHistory.empty,
  });

  final BackupSummary summary;
  final List<Garment> garments;

  /// Vazio num backup v1.
  final BackupHistory history;

  /// Bytes por (foto, variante), já verificados.
  final Map<(String, PhotoVariant), Uint8List> photoFiles;
}

/// Um valor de lavagem/rotatividade escolhido (linha de `care_policies`).
final class BackupPolicy {
  const BackupPolicy({
    required this.scope,
    required this.target,
    this.laundryAfter,
    this.rotationDays,
  });

  final PolicyScope scope;

  /// Id da categoria ou da peça.
  final String target;
  final int? laundryAfter;
  final int? rotationDays;
}

/// Histórico que acompanha as peças: só o que está ativo (desfeitos ficam
/// de fora) e só para peças que vão no backup.
final class BackupHistory {
  const BackupHistory({
    this.wears = const [],
    this.cleanings = const [],
    this.policies = const [],
  });

  static const empty = BackupHistory();

  final List<WearEvent> wears;
  final List<CleaningEvent> cleanings;
  final List<BackupPolicy> policies;
}

sealed class BackupProblem {
  const BackupProblem();
}

/// Não é um ZIP, ou não é um backup desta app.
final class NotABackup extends BackupProblem {
  const NotABackup();
}

/// Feito por uma versão mais recente da app.
final class UnsupportedBackupVersion extends BackupProblem {
  const UnsupportedBackupVersion(this.version);
  final int version;
}

/// Ficheiro em falta, alterado ou inválido. Nada é importado.
final class CorruptBackup extends BackupProblem {
  const CorruptBackup(this.detail);
  final String detail;
}

/// Exportação: fotografias que não estão neste dispositivo nem se
/// conseguiram descarregar (ex.: sem rede).
final class MissingPhotos extends BackupProblem {
  const MissingPhotos(this.count);
  final int count;
}
