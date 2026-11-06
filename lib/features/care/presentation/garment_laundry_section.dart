import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/domain/result.dart';
import '../../../l10n/app_localizations.dart';
import '../../account_sync/application/providers.dart';
import '../../wardrobe/domain/availability.dart';
import '../../wardrobe/domain/garment.dart';
import '../../wear/application/wear_providers.dart';
import '../application/care_providers.dart';
import '../domain/care_repository.dart';
import '../domain/laundry_policy.dart';
import 'care_messages.dart';
import 'policy_value_field.dart';

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
    final atCleaners = garment.availability == Availability.atCleaners;
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
        if (LaundryPolicy.asksProfessional(garment.attributes.care))
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              key: const Key('garment-laundry-professional'),
              children: [
                Icon(
                  Icons.dry_cleaning_outlined,
                  color: theme.colorScheme.tertiary,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(l10n.laundryProfessionalLabel)),
              ],
            ),
          ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _cleanedButton(context, ref, l10n, repo, atCleaners: atCleaners),
            if (!atCleaners)
              TextButton.icon(
                key: const Key('garment-to-cleaners'),
                icon: const Icon(Icons.dry_cleaning_outlined),
                label: Text(l10n.laundryToCleaners),
                onPressed: () => _toCleaners(context, ref, l10n),
              ),
          ],
        ),
        const SizedBox(height: 12),
        PolicyValueField.laundry(
          context: context,
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

  /// Fora de casa até a ir buscar: "Já veio da lavandaria" regista a
  /// limpeza e devolve-a.
  Future<void> _toCleaners(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) async {
    final wardrobe = ref.read(wardrobeRepositoryProvider);
    if (wardrobe == null) return;
    final before = garment.availability;
    final result = await wardrobe.setAvailability(
      garment.id,
      Availability.atCleaners,
    );
    if (!context.mounted || result is! Ok) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(l10n.laundryAtCleaners),
          action: SnackBarAction(
            label: l10n.wearUndo,
            onPressed: () => wardrobe.setAvailability(garment.id, before),
          ),
        ),
      );
  }

  Widget _cleanedButton(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    CareRepository repo, {
    required bool atCleaners,
  }) => OutlinedButton.icon(
    key: const Key('garment-cleaned'),
    icon: Icon(
      atCleaners
          ? Icons.dry_cleaning_outlined
          : Icons.local_laundry_service_outlined,
    ),
    label: Text(
      atCleaners ? l10n.laundryBackFromCleaners : l10n.laundryCleanedToday,
    ),
    onPressed: () async {
      final today = todayFrom(ref.read(clockProvider));
      final wardrobe = ref.read(wardrobeRepositoryProvider);
      final before = garment.availability;
      final result = await repo.recordCleaning(garment.id, today);
      if (!context.mounted || !reportCare(context, result)) return;
      // Lavada, volta a estar disponível (decisão de 2026-11-06): é
      // o único caminho de volta além de a mudar à mão.
      final restored =
          !before.isAvailable &&
          wardrobe != null &&
          await wardrobe.setAvailability(garment.id, Availability.available)
              is Ok;
      if (!context.mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              restored && atCleaners
                  ? l10n.laundryBackAvailable
                  : restored
                  ? l10n.laundryCleanedAvailable
                  : l10n.laundryCleaned,
            ),
            action: SnackBarAction(
              label: l10n.wearUndo,
              onPressed: () async {
                final last = ref.read(lastCleaningProvider(garment.id));
                if (last != null) await repo.voidCleaning(last.id);
                if (restored) {
                  await wardrobe.setAvailability(garment.id, before);
                }
              },
            ),
          ),
        );
    },
  );
}
