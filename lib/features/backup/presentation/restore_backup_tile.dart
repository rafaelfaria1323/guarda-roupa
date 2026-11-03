import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/domain/result.dart';
import '../../../l10n/app_localizations.dart';
import '../application/backup_providers.dart';
import '../data/backup_restorer.dart';
import '../domain/backup.dart';

/// Recuperar: escolher ficheiro → verificar (ficheiro e destino) → preview
/// → confirmar → aplicar numa transação. Até confirmar nada é alterado.
class RestoreBackupTile extends ConsumerStatefulWidget {
  const RestoreBackupTile({super.key});

  @override
  ConsumerState<RestoreBackupTile> createState() => _RestoreBackupTileState();
}

class _RestoreBackupTileState extends ConsumerState<RestoreBackupTile> {
  bool _busy = false;

  Future<void> _restore(BackupRestorer restorer) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final picker = ref.read(backupPickerProvider);

    final Uint8List? zip;
    try {
      zip = await picker.pick();
    } on Object {
      messenger.showSnackBar(SnackBar(content: Text(l10n.backupPickFailed)));
      return;
    }
    if (zip == null || !mounted) return; // cancelado

    setState(() => _busy = true);
    final inspected = await restorer.inspect(zip);
    if (!mounted) return;
    setState(() => _busy = false);
    final BackupContents contents;
    switch (inspected) {
      case Ok(:final value):
        contents = value;
      case Err(:final failure):
        return _explain(failure);
    }

    if (!await _confirm(contents.summary) || !mounted) return;
    setState(() => _busy = true);
    final applied = await restorer.apply(contents);
    if (!mounted) return;
    setState(() => _busy = false);
    switch (applied) {
      case Ok(value: final count):
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.backupRestored(count))),
        );
      case Err(:final failure):
        await _explain(failure);
    }
  }

  Future<bool> _confirm(BackupSummary summary) async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.backupPreviewTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.backupPreviewDate(summary.exportedAt.toLocal())),
            const SizedBox(height: 8),
            Text(l10n.backupPreviewCounts(summary.garments, summary.photos)),
            if (summary.pendingOperations > 0) ...[
              const SizedBox(height: 8),
              Text(l10n.backupPreviewPending(summary.pendingOperations)),
            ],
            const SizedBox(height: 8),
            Text(l10n.backupPreviewHow),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            key: const Key('backup-restore-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.backupRestoreConfirm),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _explain(RestoreProblem problem) {
    final l10n = AppLocalizations.of(context);
    final message = switch (problem) {
      InvalidBackupFile(problem: NotABackup()) => l10n.backupNotABackup,
      InvalidBackupFile(problem: UnsupportedBackupVersion()) =>
        l10n.backupNewerVersion,
      InvalidBackupFile() => l10n.backupCorrupt,
      AccountNotEmpty() => l10n.backupAccountNotEmpty,
      AccountNotSyncedYet() => l10n.backupNotSynced,
      RestoreFailed() => l10n.backupRestoreFailed,
    };
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.backupRestoreBlockedTitle),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.close),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final restorer = ref.watch(backupRestorerProvider);
    return ListTile(
      key: const Key('backup-restore'),
      leading: _busy
          ? const SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.settings_backup_restore),
      title: Text(_busy ? l10n.backupChecking : l10n.backupRestore),
      subtitle: Text(l10n.backupRestoreHint),
      enabled: restorer != null && !_busy,
      onTap: restorer == null ? null : () => _restore(restorer),
    );
  }
}
