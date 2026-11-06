import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../application/reminder_providers.dart';
import '../domain/push_client.dart';
import '../domain/reminder_settings.dart';

/// Definições › Lembretes: "Vestiste isto?" e "O que vestir amanhã", cada
/// um à sua hora (docs/features/lembretes.md).
class ReminderSettingsScreen extends ConsumerStatefulWidget {
  const ReminderSettingsScreen({super.key});

  @override
  ConsumerState<ReminderSettingsScreen> createState() =>
      _ReminderSettingsScreenState();
}

class _ReminderSettingsScreenState
    extends ConsumerState<ReminderSettingsScreen> {
  var _busy = false;

  Future<void> _apply(ReminderSettings next) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    // Sem esperas antes: no iPhone o pedido de autorização tem de vir do toque.
    final outcome = await ref.read(reminderStateProvider.notifier).apply(next);
    if (!mounted) return;
    setState(() => _busy = false);
    final message = switch (outcome) {
      ReminderOutcome.ok => null,
      ReminderOutcome.denied => l10n.remindersDenied,
      ReminderOutcome.unsupported => l10n.remindersUnsupported,
      ReminderOutcome.failed => l10n.remindersFailed,
    };
    if (message != null) {
      messenger.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<ClockTime?> _pickTime(ClockTime initial) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: initial.hour, minute: initial.minute),
    );
    return picked == null ? null : ClockTime(picked.hour, picked.minute);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final support = ref.watch(pushClientProvider).support;
    final state = ref.watch(reminderStateProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.remindersTitle)),
      body: switch (state) {
        AsyncData(value: null) || AsyncError() => Padding(
          padding: const EdgeInsets.all(16),
          child: Text(l10n.remindersFailed),
        ),
        AsyncData(value: final s?) => ListView(
          key: const Key('reminders-list'),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text(
                l10n.remindersIntro,
                style: theme.textTheme.bodyMedium,
              ),
            ),
            if (support != PushSupport.available && !s.thisDevice)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Card.outlined(
                  child: ListTile(
                    key: const Key('reminders-support'),
                    leading: const Icon(Icons.info_outline),
                    title: Text(
                      support == PushSupport.needsInstall
                          ? l10n.remindersNeedsInstall
                          : l10n.remindersUnsupported,
                    ),
                  ),
                ),
              ),
            ..._reminder(
              id: 'wear',
              title: l10n.remindersWearCheck,
              hint: l10n.remindersWearCheckHint,
              at: s.settings.wearCheckAt,
              fallback: ReminderSettings.defaultWearCheckAt,
              enabled: support == PushSupport.available || s.thisDevice,
              update: (t) => s.settings.copyWith(wearCheckAt: () => t),
            ),
            ..._reminder(
              id: 'eve',
              title: l10n.remindersEve,
              hint: l10n.remindersEveHint,
              at: s.settings.eveAt,
              fallback: ReminderSettings.defaultEveAt,
              enabled: support == PushSupport.available || s.thisDevice,
              update: (t) => s.settings.copyWith(eveAt: () => t),
            ),
            if (s.settings.anyOn)
              s.thisDevice
                  ? ListTile(
                      key: const Key('reminders-this-device'),
                      leading: const Icon(Icons.notifications_active_outlined),
                      title: Text(l10n.remindersThisDevice),
                    )
                  : ListTile(
                      key: const Key('reminders-other-device'),
                      leading: const Icon(Icons.notifications_off_outlined),
                      title: Text(l10n.remindersOtherDevice),
                      trailing: support == PushSupport.available
                          ? TextButton(
                              key: const Key('reminders-receive-here'),
                              onPressed: _busy
                                  ? null
                                  : () => _apply(s.settings),
                              child: Text(l10n.remindersReceiveHere),
                            )
                          : null,
                    ),
          ],
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  List<Widget> _reminder({
    required String id,
    required String title,
    required String hint,
    required ClockTime? at,
    required ClockTime fallback,
    required bool enabled,
    required ReminderSettings Function(ClockTime?) update,
  }) {
    final l10n = AppLocalizations.of(context);
    return [
      SwitchListTile(
        key: Key('reminders-$id'),
        title: Text(title),
        subtitle: Text(hint),
        value: at != null,
        onChanged: _busy || !enabled
            ? null
            : (on) => _apply(update(on ? fallback : null)),
      ),
      if (at != null)
        ListTile(
          key: Key('reminders-$id-time'),
          contentPadding: const EdgeInsetsDirectional.only(start: 32, end: 16),
          leading: const Icon(Icons.schedule),
          title: Text(l10n.remindersAt(at.hhmm)),
          enabled: !_busy,
          onTap: () async {
            final picked = await _pickTime(at);
            if (picked != null && picked != at) await _apply(update(picked));
          },
        ),
    ];
  }
}

/// "Vestiste isto? às 21:30 · Véspera às 20:00", ou "Desligados".
String reminderSummary(AppLocalizations l10n, ReminderSettings s) {
  final parts = [
    if (s.wearCheckAt case final t?) l10n.remindersSummaryWear(t.hhmm),
    if (s.eveAt case final t?) l10n.remindersSummaryEve(t.hhmm),
  ];
  return parts.isEmpty ? l10n.remindersOff : parts.join(' · ');
}
