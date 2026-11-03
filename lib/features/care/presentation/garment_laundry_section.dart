import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../wardrobe/domain/garment.dart';
import '../../wear/application/wear_providers.dart';
import '../application/care_providers.dart';
import '../domain/laundry_policy.dart';
import 'care_messages.dart';
import 'laundry_after_field.dart';

/// Lavagem na ficha da peça: utilizações desde a última limpeza, aviso
/// (informativo), "Lavei hoje" e o aviso escolhido para esta peça.
class GarmentLaundrySection extends ConsumerWidget {
  const GarmentLaundrySection({required this.garment, super.key});

  final Garment garment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final state = ref.watch(laundryStatesProvider)?[garment.id];
    final policies = ref.watch(carePoliciesProvider).value;
    final repo = ref.watch(careRepositoryProvider);
    if (state == null || policies == null || repo == null) {
      return const SizedBox.shrink();
    }
    final lastCleaned = state.lastCleanedOn;
    final categoryValue =
        policies.laundryByCategory[garment.category] ??
        LaundryPolicy.defaultFor(garment.category);

    return Column(
      key: const Key('garment-laundry'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.laundryTitle, style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          lastCleaned == null
              ? l10n.laundryUsesNoCleaning(state.usesSinceCleaning)
              : l10n.laundryUses(state.usesSinceCleaning),
          key: const Key('garment-laundry-uses'),
        ),
        if (lastCleaned != null)
          Text(l10n.laundryLastCleaned(lastCleaned.toLocalDateTime())),
        if (state.washRecommended)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              key: const Key('garment-laundry-recommended'),
              children: [
                Icon(
                  Icons.local_laundry_service_outlined,
                  color: theme.colorScheme.tertiary,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(l10n.laundryRecommended)),
              ],
            ),
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const Key('garment-cleaned'),
          icon: const Icon(Icons.local_laundry_service_outlined),
          label: Text(l10n.laundryCleanedToday),
          onPressed: () async {
            final today = todayFrom(ref.read(clockProvider));
            final result = await repo.recordCleaning(garment.id, today);
            if (!context.mounted || !reportCare(context, result)) return;
            final messenger = ScaffoldMessenger.of(context);
            messenger
              ..hideCurrentSnackBar()
              ..showSnackBar(
                SnackBar(
                  content: Text(l10n.laundryCleaned),
                  action: SnackBarAction(
                    label: l10n.wearUndo,
                    onPressed: () async {
                      final last = ref.read(lastCleaningProvider(garment.id));
                      if (last != null) await repo.voidCleaning(last.id);
                    },
                  ),
                ),
              );
          },
        ),
        const SizedBox(height: 12),
        LaundryAfterField(
          key: ValueKey(
            'garment-laundry-after-${policies.laundryByGarment[garment.id]}',
          ),
          value: policies.laundryByGarment[garment.id],
          defaultValue: categoryValue,
          onChanged: (value) async {
            final result = await repo.setGarmentLaundry(garment.id, value);
            if (context.mounted) reportCare(context, result);
          },
        ),
      ],
    );
  }
}
