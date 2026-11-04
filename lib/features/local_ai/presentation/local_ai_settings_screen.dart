import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../application/local_ai_providers.dart';
import '../domain/local_model.dart';

/// Descarregar ou remover os modelos de IA local (P-14), com o tamanho e a
/// licença à vista. Nada se descarrega sem um toque aqui.
class LocalAiSettingsScreen extends ConsumerWidget {
  const LocalAiSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.localAiTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(l10n.localAiIntro),
          if (kIsWeb) ...[
            const SizedBox(height: 8),
            Text(l10n.localAiDataNote, style: theme.textTheme.bodySmall),
          ],
          const SizedBox(height: 16),
          _ModelCard(
            model: LocalModels.background,
            name: 'U²-Netp',
            title: l10n.localAiBackgroundTitle,
            body: l10n.localAiBackgroundBody,
          ),
        ],
      ),
    );
  }
}

class _ModelCard extends ConsumerWidget {
  const _ModelCard({
    required this.model,
    required this.name,
    required this.title,
    required this.body,
  });

  final LocalModel model;
  final String name;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final state = ref.watch(localModelProvider(model));
    final notifier = ref.read(localModelProvider(model).notifier);
    final size =
        '${(model.bytes / 1e6).toStringAsFixed(1).replaceAll('.', ',')} MB';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(body),
            const SizedBox(height: 4),
            Text(
              l10n.localAiModelInfo(name, size, model.license),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            switch (state) {
              // Rápido; um indicador só piscaria.
              ModelChecking() => const SizedBox.shrink(),
              ModelDownloading(:final progress) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LinearProgressIndicator(value: progress),
                  const SizedBox(height: 4),
                  Text(l10n.localAiDownloading((progress * 100).floor())),
                ],
              ),
              ModelAbsent(:final failed) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (failed) ...[
                    Text(
                      l10n.localAiFailed,
                      key: Key('local-model-failed-${model.id}'),
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                    const SizedBox(height: 8),
                  ],
                  FilledButton.icon(
                    key: Key('local-model-download-${model.id}'),
                    onPressed: notifier.download,
                    icon: const Icon(Icons.download_outlined),
                    label: Text('${l10n.localAiDownload} ($size)'),
                  ),
                ],
              ),
              ModelReady() => Row(
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(l10n.localAiReady)),
                  TextButton(
                    key: Key('local-model-remove-${model.id}'),
                    onPressed: notifier.remove,
                    child: Text(l10n.localAiRemove),
                  ),
                ],
              ),
            },
          ],
        ),
      ),
    );
  }
}
