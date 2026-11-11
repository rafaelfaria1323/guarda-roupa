import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/account_sync/application/providers.dart';
import '../../l10n/app_localizations.dart';
import 'diagnostics_log.dart';
import 'diagnostics_store_io.dart'
    if (dart.library.js_interop) 'diagnostics_store_web.dart';

/// A versão publicada (o commit), posta na build por `tool/web/build_pwa.sh`.
const buildId = String.fromEnvironment('BUILD_ID', defaultValue: 'local');

final diagnosticsLogProvider = Provider<DiagnosticsLog>(
  (ref) => DiagnosticsLog.instance,
);

/// Definições › Diagnóstico: a versão, o estado da sincronização e os
/// últimos erros, para copiar e mandar a quem ajuda. Nada é enviado
/// sozinho.
class DiagnosticsScreen extends ConsumerWidget {
  const DiagnosticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final log = ref.watch(diagnosticsLogProvider);
    final sync = ref.watch(syncSummaryProvider);
    final header = [
      'fio $buildId',
      platformDescription(),
      'sync: ${[if (!sync.configured) 'off' else if (sync.connected) 'on' else 'offline', 'pendentes ${sync.pendingOperations}', 'conflitos ${sync.conflicts}', if (sync.lastSyncedAt case final at?) 'última ${at.toUtc().toIso8601String()}', if (sync.error case final e?) 'erro ${DiagnosticsLog.redact('$e')}'].join(', ')}',
    ];

    return ListenableBuilder(
      listenable: log,
      builder: (context, _) => _body(context, l10n, log, header),
    );
  }

  Widget _body(
    BuildContext context,
    AppLocalizations l10n,
    DiagnosticsLog log,
    List<String> header,
  ) {
    final theme = Theme.of(context);
    final entries = log.entries;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.diagnosticsTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(l10n.diagnosticsIntro, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: SelectableText(
                header.join('\n'),
                key: const Key('diagnostics-header'),
                style: theme.textTheme.bodySmall,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                key: const Key('diagnostics-copy'),
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  await Clipboard.setData(
                    ClipboardData(text: log.report(header)),
                  );
                  messenger.showSnackBar(
                    SnackBar(content: Text(l10n.diagnosticsCopied)),
                  );
                },
                icon: const Icon(Icons.copy),
                label: Text(l10n.diagnosticsCopy),
              ),
              if (entries.isNotEmpty)
                OutlinedButton.icon(
                  key: const Key('diagnostics-clear'),
                  onPressed: log.clear,
                  icon: const Icon(Icons.delete_outline),
                  label: Text(l10n.diagnosticsClear),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (entries.isEmpty)
            Text(
              l10n.diagnosticsEmpty,
              key: const Key('diagnostics-empty'),
              style: theme.textTheme.bodyMedium,
            )
          else
            for (final (i, e) in entries.indexed)
              Card(
                key: Key('diagnostics-entry-$i'),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${MaterialLocalizations.of(context).formatShortDate(e.at.toLocal())} '
                        '${TimeOfDay.fromDateTime(e.at.toLocal()).format(context)} · ${e.where}',
                        style: theme.textTheme.labelMedium,
                      ),
                      const SizedBox(height: 4),
                      SelectableText(
                        e.message,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}
