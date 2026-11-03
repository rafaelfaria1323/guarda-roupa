import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../wardrobe/domain/garment.dart';
import '../application/care_providers.dart';
import '../domain/rotation_policy.dart';
import 'care_messages.dart';
import 'policy_value_field.dart';

/// Rotação na ficha da peça: quando volta a ser elegível e o intervalo
/// escolhido para esta peça.
class GarmentRotationSection extends ConsumerWidget {
  const GarmentRotationSection({required this.garment, super.key});

  final Garment garment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(rotationStatesProvider)?[garment.id];
    final policies = ref.watch(carePoliciesProvider).value;
    final repo = ref.watch(careRepositoryProvider);
    if (state == null || policies == null || repo == null) {
      return const SizedBox.shrink();
    }
    final from = state.eligibleFrom;
    final categoryValue =
        policies.rotationByCategory[garment.category] ??
        RotationPolicy.defaultFor(garment.category);
    return Column(
      key: const Key('garment-rotation'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.rotationTitle, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          from == null
              ? l10n.rotationEligible
              : l10n.rotationEligibleFrom(from.toLocalDateTime()),
          key: const Key('garment-rotation-state'),
        ),
        const SizedBox(height: 12),
        PolicyValueField.rotation(
          context: context,
          key: ValueKey(
            'garment-rotation-days-${policies.rotationByGarment[garment.id]}',
          ),
          value: policies.rotationByGarment[garment.id],
          defaultValue: categoryValue,
          onChanged: (value) async {
            final result = await repo.setGarmentRotation(garment.id, value);
            if (context.mounted) reportCare(context, result);
          },
        ),
      ],
    );
  }
}
