import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../backup/presentation/export_backup_tile.dart';
import '../application/providers.dart';
import 'sync_status.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final user = ref.watch(currentUserProvider).value;
    final sync = ref.watch(syncSummaryProvider);
    final (syncIcon, syncLabel) = describeSync(l10n, sync);
    final email = user?.email;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settings)),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.account_circle_outlined),
            title: Text(l10n.settingsAccount),
            subtitle: Text(
              email == null
                  ? l10n.settingsSignedIn
                  : l10n.settingsSignedInAs(email),
            ),
          ),
          ListTile(leading: Icon(syncIcon), title: Text(syncLabel)),
          if (sync.conflicts > 0)
            ListTile(
              leading: const Icon(Icons.report_outlined),
              title: Text(l10n.syncConflicts(sync.conflicts)),
            ),
          ListTile(
            leading: const Icon(Icons.logout),
            title: Text(l10n.settingsSignOut),
            onTap: () => _confirmSignOut(context, ref),
          ),
          const Divider(height: 1),
          ListTile(
            title: Text(
              l10n.settingsBackup,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            dense: true,
          ),
          const ExportBackupTile(),
        ],
      ),
    );
  }

  /// ADR-008: sem pendências, confirma e apaga a base local da conta; com
  /// pendências, bloqueia e recomenda sincronizar primeiro.
  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final sync = ref.read(syncSummaryProvider);
    final pending = sync.pendingOperations;

    if (pending == 0) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n.signOutTitle),
          content: Text(l10n.signOutBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l10n.settingsSignOut),
            ),
          ],
        ),
      );
      if (ok != true) return;
    } else {
      final choice = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n.signOutPendingTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.signOutPendingBody(pending)),
              if (!sync.configured) ...[
                const SizedBox(height: 12),
                Text(l10n.signOutSyncUnavailable),
              ],
              const SizedBox(height: 12),
              Text(
                l10n.signOutExportSoon,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l10n.signOutDiscard),
            ),
            FilledButton(
              autofocus: true,
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.signOutSyncFirst),
            ),
          ],
        ),
      );
      if (choice != true || !context.mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n.signOutDiscardConfirmTitle),
          content: Text(l10n.signOutDiscardConfirmBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: Text(l10n.signOutDiscard),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    await signOut(ref);
  }
}
