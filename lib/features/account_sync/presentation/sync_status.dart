import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../application/providers.dart';

/// Ícone e texto que descrevem o estado de sincronização, sem otimismo:
/// "guardado neste dispositivo" não é "aceite pelo servidor".
(IconData, String) describeSync(AppLocalizations l10n, SyncSummary sync) {
  if (!sync.configured) return (Icons.cloud_off_outlined, l10n.syncLocalOnly);
  if (sync.error != null) return (Icons.sync_problem_outlined, l10n.syncError);
  if (sync.pendingOperations > 0) {
    return (
      Icons.cloud_upload_outlined,
      l10n.syncPending(sync.pendingOperations),
    );
  }
  if (!sync.connected) return (Icons.cloud_off_outlined, l10n.syncOffline);
  return (Icons.cloud_done_outlined, l10n.syncSynced);
}

class SyncStatusIcon extends StatelessWidget {
  const SyncStatusIcon({
    required this.sync,
    required this.onPressed,
    super.key,
  });

  final SyncSummary sync;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final (icon, label) = describeSync(AppLocalizations.of(context), sync);
    return IconButton(
      tooltip: label,
      onPressed: onPressed,
      icon: Badge(
        isLabelVisible: sync.configured && sync.pendingOperations > 0,
        label: Text('${sync.pendingOperations}'),
        child: Icon(icon),
      ),
    );
  }
}
