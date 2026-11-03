import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settings)),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.sync_outlined),
            title: Text(l10n.settingsAccount),
            subtitle: Text(l10n.settingsAccountHint),
            enabled: false,
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.backup_outlined),
            title: Text(l10n.settingsBackup),
            subtitle: Text(l10n.settingsBackupHint),
            enabled: false,
          ),
        ],
      ),
    );
  }
}
