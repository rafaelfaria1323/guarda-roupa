import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/domain/result.dart';
import '../../../l10n/app_localizations.dart';
import '../application/backup_providers.dart';
import '../data/backup_restorer.dart';
import '../domain/backup.dart';

/// Recuperar: escolher ficheiro → verificar o ficheiro e comparar com a
/// conta → preview (o que se acrescenta; peças apagadas depois do backup só
/// se marcadas) → confirmar → juntar numa transação. Até confirmar nada é
/// alterado.
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
    final RestorePreview preview;
    switch (inspected) {
      case Ok(:final value):
        preview = value;
      case Err(:final failure):
        return _explain(failure);
    }

    final restoreRemoved = await _confirm(preview);
    if (restoreRemoved == null || !mounted) return;
    setState(() => _busy = true);
    final applied = await restorer.apply(
      preview,
      restoreRemoved: restoreRemoved,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    switch (applied) {
      case Ok(value: final plan):
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.backupRestored(plan.newGarments.length))),
        );
      case Err(:final failure):
        await _explain(failure);
    }
  }

  /// `null` se cancelar; senão, se recupera também as peças apagadas
  /// depois do backup.
  Future<bool?> _confirm(RestorePreview preview) {
    final l10n = AppLocalizations.of(context);
    final summary = preview.contents.summary;
    var restoreRemoved = preview.accountEmpty;
    return showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final plan = preview.plan(restoreRemoved: restoreRemoved);
          final h = plan.history;
          final removed = preview.withRemoved.removedGarments.length;
          final images = h.inspirations.where((i) => i.image != null).length;
          return AlertDialog(
            title: Text(l10n.backupPreviewTitle),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.backupPreviewDate(summary.exportedAt.toLocal())),
                  if (plan.newGarments.isNotEmpty || plan.present.isEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      l10n.backupPreviewCounts(
                        plan.newGarments.length,
                        plan.photos,
                      ),
                      key: const Key('backup-preview-counts'),
                    ),
                  ],
                  if (plan.present.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      l10n.backupPreviewPresent(plan.present.length),
                      key: const Key('backup-preview-present'),
                    ),
                  ],
                  if (removed > 0)
                    CheckboxListTile(
                      key: const Key('backup-restore-removed'),
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: restoreRemoved,
                      onChanged: (v) =>
                          setDialogState(() => restoreRemoved = v ?? false),
                      title: Text(l10n.backupPreviewRemoved(removed)),
                    ),
                  if (h.wears.isNotEmpty || h.cleanings.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      l10n.backupPreviewHistory(
                        h.wears.length,
                        h.cleanings.length,
                      ),
                      key: const Key('backup-preview-history'),
                    ),
                  ],
                  if (h.outfits.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      l10n.backupPreviewOutfits(h.outfits.length),
                      key: const Key('backup-preview-outfits'),
                    ),
                  ],
                  if (h.inspirations.isNotEmpty ||
                      h.preferences.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      l10n.backupPreviewStyle(
                        h.inspirations.length,
                        h.preferences.length,
                      ),
                      key: const Key('backup-preview-style'),
                    ),
                    if (images > 0)
                      Text(
                        l10n.backupPreviewStyleImages(images),
                        key: const Key('backup-preview-style-images'),
                      ),
                  ],
                  if (summary.pendingOperations > 0) ...[
                    const SizedBox(height: 8),
                    Text(l10n.backupPreviewPending(summary.pendingOperations)),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    plan.nothingToAdd
                        ? l10n.backupPreviewNothing
                        : l10n.backupPreviewHow,
                    key: const Key('backup-preview-how'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(l10n.cancel),
              ),
              FilledButton(
                key: const Key('backup-restore-confirm'),
                onPressed: plan.nothingToAdd
                    ? null
                    : () => Navigator.pop(context, restoreRemoved),
                child: Text(l10n.backupRestoreConfirm),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _explain(RestoreProblem problem) {
    final l10n = AppLocalizations.of(context);
    final message = switch (problem) {
      InvalidBackupFile(problem: NotABackup()) => l10n.backupNotABackup,
      InvalidBackupFile(problem: UnsupportedBackupVersion()) =>
        l10n.backupNewerVersion,
      InvalidBackupFile() => l10n.backupCorrupt,
      NeedsNetwork() => l10n.backupNeedsNetwork,
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
