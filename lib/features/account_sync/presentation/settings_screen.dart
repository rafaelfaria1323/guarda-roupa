import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../engine/application/suggestion_providers.dart';
import '../../local_ai/application/local_ai_providers.dart';
import '../../local_ai/domain/local_model.dart';
import '../../reminders/application/reminder_providers.dart';
import '../../reminders/presentation/reminder_settings_screen.dart';
import '../../../app/router.dart';
import '../../../app/theme_mode.dart';
import '../../../l10n/app_localizations.dart';
import '../../backup/presentation/export_backup_tile.dart';
import '../../backup/presentation/restore_backup_tile.dart';
import '../../weather/application/weather_providers.dart';
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
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _Group(
            title: l10n.settingsAccount,
            children: [
              ListTile(
                leading: const Icon(Icons.account_circle_outlined),
                title: Text(
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
            ],
          ),
          _Group(
            title: l10n.themeTitle,
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<ThemeMode>(
                    key: const Key('theme-mode'),
                    showSelectedIcon: false,
                    segments: [
                      for (final m in [
                        ThemeMode.system,
                        ThemeMode.light,
                        ThemeMode.dark,
                      ])
                        ButtonSegment(
                          value: m,
                          label: Text(
                            l10n.themeMode(m.name),
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.fade,
                          ),
                        ),
                    ],
                    selected: {ref.watch(themeModeProvider)},
                    onSelectionChanged: (s) =>
                        ref.read(themeModeProvider.notifier).set(s.single),
                  ),
                ),
              ),
            ],
          ),
          _Group(
            title: l10n.settingsPreferences,
            children: [
              if (ref.watch(reminderBackendProvider) != null)
                ListTile(
                  key: const Key('reminder-settings'),
                  leading: const Icon(Icons.notifications_outlined),
                  title: Text(l10n.remindersTitle),
                  subtitle: Text(switch (ref
                      .watch(reminderStateProvider)
                      .value) {
                    final s? => reminderSummary(l10n, s.settings),
                    null => '',
                  }),
                  onTap: () => context.push(AppRoutes.reminderSettings),
                ),
              ListTile(
                key: const Key('weather-location'),
                leading: const Icon(Icons.place_outlined),
                title: Text(l10n.weatherLocationTitle),
                subtitle: Text(
                  ref.watch(weatherLocationProvider).value?.name ?? '',
                ),
                onTap: () => context.push(AppRoutes.weatherLocation),
              ),
              ListTile(
                key: const Key('comfort-settings'),
                leading: const Icon(Icons.thermostat_outlined),
                title: Text(l10n.comfortTitle),
                subtitle: Text(switch (ref
                    .watch(comfortThresholdsProvider)
                    .value) {
                  final t? => l10n.comfortSummary(
                    t.hotFromC.round(),
                    t.coldBelowC.round(),
                    t.windyFromKmh.round(),
                  ),
                  null => '',
                }),
                onTap: () => context.push(AppRoutes.comfortSettings),
              ),
              ListTile(
                key: const Key('care-settings'),
                leading: const Icon(Icons.local_laundry_service_outlined),
                title: Text(l10n.careSettingsTitle),
                onTap: () => context.push(AppRoutes.careSettings),
              ),
              ListTile(
                key: const Key('local-ai-settings'),
                leading: const Icon(Icons.auto_awesome_outlined),
                title: Text(l10n.localAiTitle),
                subtitle: Text(
                  [LocalModels.background, LocalModels.category].any(
                        (m) => ref.watch(localModelProvider(m)) is ModelReady,
                      )
                      ? l10n.localAiSummaryOn
                      : l10n.localAiSummaryOff,
                ),
                onTap: () => context.push(AppRoutes.localAiSettings),
              ),
            ],
          ),
          _Group(
            title: l10n.settingsBackup,
            children: const [ExportBackupTile(), RestoreBackupTile()],
          ),
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

/// Um grupo de Definições: título por cima e as linhas num cartão.
class _Group extends StatelessWidget {
  const _Group({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
            child: Text(title, style: theme.textTheme.titleSmall),
          ),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (final (i, child) in children.indexed) ...[
                  if (i > 0) const Divider(height: 1, indent: 56),
                  child,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
