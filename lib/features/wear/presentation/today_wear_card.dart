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
import '../../wardrobe/presentation/garment_cutout.dart';
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

    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return StreamBuilder<List<WearEvent>>(
      stream: repo.watchDay(today),
      builder: (context, events) => StreamBuilder<List<Garment>>(
        // Inclui arquivadas: uma peça usada hoje pode ter sido arquivada.
        stream: wardrobe.watchGarments(
          const GarmentFilter(includeArchived: true),
        ),
        builder: (context, garments) {
          final list = events.data ?? const <WearEvent>[];
          final byId = {for (final g in garments.data ?? <Garment>[]) g.id: g};
          if (list.isEmpty) {
            // Ainda nada: uma linha discreta, a sugestão é o principal.
            return Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(l10n.wearTodayNone, style: muted),
                OutlinedButton(
                  key: const Key('wear-today'),
                  onPressed: () => context.push(AppRoutes.wear),
                  child: Text(l10n.wearTodayButton),
                ),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.wearTodayTitle, style: theme.textTheme.titleLarge),
              const SizedBox(height: 10),
              for (final event in list) _EventRow(event: event, garments: byId),
              TextButton(
                key: const Key('wear-today'),
                style: TextButton.styleFrom(padding: EdgeInsets.zero),
                onPressed: () => context.push(AppRoutes.wear),
                child: Text(l10n.wearAnother),
              ),
            ],
          );
        },
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
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final id in event.garmentIds)
                  Padding(
                    padding: const EdgeInsets.only(right: 14),
                    child: SizedBox(
                      width: 76,
                      child: Column(
                        children: [
                          if (garments[id] case final g?)
                            GarmentCutout(garment: g, size: 64)
                          else
                            const SizedBox.square(
                              dimension: 64,
                              child: Icon(Icons.help_outline),
                            ),
                          const SizedBox(height: 6),
                          Text(
                            garmentLabel(l10n, garments[id]),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
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
