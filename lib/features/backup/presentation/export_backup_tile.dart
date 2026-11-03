import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/domain/result.dart';
import '../../../l10n/app_localizations.dart';
import '../application/backup_providers.dart';
import '../data/backup_exporter.dart';
import '../domain/backup.dart';
import '../domain/backup_saver.dart';

/// Exportar: gera o ZIP (verificado) e abre o "Guardar como" do sistema.
/// O resultado é sempre visível: guardado, transferência iniciada (Web) ou
/// o motivo da falha. Cancelar o diálogo não mostra nada.
class ExportBackupTile extends ConsumerStatefulWidget {
  const ExportBackupTile({super.key});

  @override
  ConsumerState<ExportBackupTile> createState() => _ExportBackupTileState();
}

class _ExportBackupTileState extends ConsumerState<ExportBackupTile> {
  bool _busy = false;

  Future<void> _export(BackupExporter exporter) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final saver = ref.read(backupSaverProvider);
    setState(() => _busy = true);
    String? message;
    try {
      final now = DateTime.now();
      switch (await exporter.export(now: now)) {
        case Ok(value: final zip):
          message = switch (await saver.save(backupFileName(now), zip)) {
            SaveOutcome.saved => l10n.backupSaved,
            SaveOutcome.downloadStarted => l10n.backupDownloadStarted,
            SaveOutcome.cancelled => null,
          };
        case Err(failure: MissingPhotos(:final count)):
          message = l10n.backupMissingPhotos(count);
        case Err():
          message = l10n.backupFailed;
      }
    } on Object {
      message = l10n.backupFailed;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (message != null) {
      messenger.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final exporter = ref.watch(backupExporterProvider);
    return ListTile(
      key: const Key('backup-export'),
      leading: _busy
          ? const SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.backup_outlined),
      title: Text(_busy ? l10n.backupExporting : l10n.backupExport),
      subtitle: Text(l10n.settingsBackupHint),
      enabled: exporter != null && !_busy,
      onTap: exporter == null ? null : () => _export(exporter),
    );
  }
}
