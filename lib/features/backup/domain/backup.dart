import 'dart:typed_data';

import '../../wardrobe/domain/garment.dart';
import '../../wardrobe/domain/garment_photo.dart';

/// Formato do ficheiro de backup (docs/features/backups-e-recuperacao.md).
///
/// ZIP com `manifest.json` (formato, versão, data, contagens e a lista de
/// ficheiros com tamanho e SHA-256), `data/garments.json` e as fotografias
/// em `photos/{id}/main.jpg|thumb.jpg`. Sem tokens, chaves ou URLs.
abstract final class BackupFormat {
  static const name = 'guarda-roupa-backup';

  /// Sobe quando o leitor antigo deixar de perceber o conteúdo.
  static const version = 1;

  static const manifestPath = 'manifest.json';
  static const garmentsPath = 'data/garments.json';

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
  });

  final DateTime exportedAt;
  final int garments;
  final int photos;

  /// Alterações ainda por sincronizar no momento da exportação (estão
  /// incluídas no backup, mas não tinham chegado à cloud).
  final int pendingOperations;
}

final class BackupContents {
  const BackupContents({
    required this.summary,
    required this.garments,
    required this.photoFiles,
  });

  final BackupSummary summary;
  final List<Garment> garments;

  /// Bytes por (foto, variante), já verificados.
  final Map<(String, PhotoVariant), Uint8List> photoFiles;
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
