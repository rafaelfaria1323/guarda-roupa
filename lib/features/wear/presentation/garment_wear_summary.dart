import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../wardrobe/domain/garment.dart';
import '../application/wear_providers.dart';
import '../domain/wear_event.dart';

/// Quantas vezes a peça foi usada e quando, a partir das utilizações
/// confirmadas.
class GarmentWearSummary extends ConsumerWidget {
  const GarmentWearSummary({required this.garmentId, super.key});

  static const _shown = 10;

  final GarmentId garmentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final repo = ref.watch(wearRepositoryProvider);
    if (repo == null) return const SizedBox.shrink();
    return StreamBuilder<List<WearEvent>>(
      stream: repo.watchGarmentHistory(garmentId),
      builder: (context, snapshot) {
        final events = snapshot.data;
        if (events == null) return const SizedBox.shrink();
        return Column(
          key: const Key('garment-wear-history'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.garmentWearHistory,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              l10n.garmentWearCount(events.length),
              key: const Key('garment-wear-count'),
            ),
            for (final e in events.take(_shown))
              Text('• ${l10n.wearDay(e.wornOn.toLocalDateTime())}'),
            if (events.length > _shown)
              Text(l10n.garmentWearMore(events.length - _shown)),
          ],
        );
      },
    );
  }
}
