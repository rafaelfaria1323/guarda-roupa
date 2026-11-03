import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../l10n/app_localizations.dart';
import '../../account_sync/application/providers.dart';
import '../../wardrobe/domain/garment.dart';
import '../../wardrobe/domain/garment_filter.dart';
import '../application/wear_providers.dart';
import '../domain/wear_event.dart';
import 'wear_messages.dart';

/// "Vesti hoje" (P-08): o que foi realmente usado hoje, com corrigir e
/// desfazer. Só isto conta como utilização; planear não conta.
class TodayWearCard extends ConsumerWidget {
  const TodayWearCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final repo = ref.watch(wearRepositoryProvider);
    final wardrobe = ref.watch(wardrobeRepositoryProvider);
    if (repo == null || wardrobe == null) return const SizedBox.shrink();
    final today = todayFrom(ref.watch(clockProvider));
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: StreamBuilder<List<WearEvent>>(
          stream: repo.watchDay(today),
          builder: (context, events) => StreamBuilder<List<Garment>>(
            // Inclui arquivadas: uma peça usada hoje pode ter sido arquivada.
            stream: wardrobe.watchGarments(
              const GarmentFilter(includeArchived: true),
            ),
            builder: (context, garments) {
              final list = events.data ?? const <WearEvent>[];
              final byId = {
                for (final g in garments.data ?? <Garment>[]) g.id: g,
              };
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.wearTodayTitle, style: theme.textTheme.titleMedium),
                  Text(l10n.wearDay(today.toLocalDateTime())),
                  const SizedBox(height: 12),
                  if (list.isEmpty) Text(l10n.wearTodayNone),
                  for (final event in list)
                    _EventRow(event: event, garments: byId),
                  const SizedBox(height: 12),
                  if (list.isEmpty)
                    FilledButton.icon(
                      key: const Key('wear-today'),
                      onPressed: () => context.push(AppRoutes.wear),
                      icon: const Icon(Icons.checkroom),
                      label: Text(l10n.wearTodayButton),
                    )
                  else
                    TextButton.icon(
                      key: const Key('wear-today'),
                      onPressed: () => context.push(AppRoutes.wear),
                      icon: const Icon(Icons.add),
                      label: Text(l10n.wearAnother),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _EventRow extends ConsumerWidget {
  const _EventRow({required this.event, required this.garments});

  final WearEvent event;
  final Map<GarmentId, Garment> garments;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      key: Key('wear-event-${event.id}'),
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final id in event.garmentIds)
                Chip(label: Text(garmentLabel(l10n, garments[id]))),
            ],
          ),
          Row(
            children: [
              TextButton(
                key: Key('wear-correct-${event.id}'),
                onPressed: () => context.push(AppRoutes.correctWear(event.id)),
                child: Text(l10n.wearCorrect),
              ),
              TextButton(
                key: Key('wear-undo-${event.id}'),
                onPressed: () async {
                  final repo = ref.read(wearRepositoryProvider);
                  if (repo == null) return;
                  final result = await repo.voidWear(event.id);
                  if (!context.mounted || !reportWear(context, result)) return;
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(SnackBar(content: Text(l10n.wearUndone)));
                },
                child: Text(l10n.wearUndo),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Nome da peça, a categoria se não tiver nome, ou "peça eliminada".
String garmentLabel(AppLocalizations l10n, Garment? garment) {
  if (garment == null) return l10n.wearDeletedGarment;
  return garment.name ?? l10n.categoryLabel(garment.category.id);
}
