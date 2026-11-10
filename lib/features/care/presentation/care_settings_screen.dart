import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../wardrobe/domain/garment_category.dart';
import '../application/care_providers.dart';
import '../domain/laundry_policy.dart';
import '../domain/rotation_policy.dart';
import 'care_messages.dart';
import 'policy_value_field.dart';

/// Aviso de lavagem (P-07) e intervalo de rotação (P-06) por categoria.
/// Cada peça pode ter os seus, na ficha.
class CareSettingsScreen extends ConsumerWidget {
  const CareSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final policies = ref.watch(carePoliciesProvider).value;
    final repo = ref.watch(careRepositoryProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.careSettingsTitle)),
      body: policies == null || repo == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(l10n.careSettingsHint, style: muted),
                const SizedBox(height: 8),
                Text(l10n.rotationSettingsHint, style: muted),
                for (final c in GarmentCategory.values) ...[
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: Text(
                              l10n.categoryLabel(c.id),
                              style: theme.textTheme.titleSmall,
                            ),
                          ),
                          const SizedBox(height: 12),
                          PolicyValueField.laundry(
                            context: context,
                            key: ValueKey(
                              'laundry-category-${c.id}-'
                              '${policies.laundryByCategory[c]}',
                            ),
                            value: policies.laundryByCategory[c],
                            defaultValue: LaundryPolicy.defaultFor(c),
                            onChanged: (value) async {
                              final r = await repo.setCategoryLaundry(c, value);
                              if (context.mounted) reportCare(context, r);
                            },
                          ),
                          const SizedBox(height: 12),
                          PolicyValueField.rotation(
                            context: context,
                            key: ValueKey(
                              'rotation-category-${c.id}-'
                              '${policies.rotationByCategory[c]}',
                            ),
                            value: policies.rotationByCategory[c],
                            defaultValue: RotationPolicy.defaultFor(c),
                            onChanged: (value) async {
                              final r = await repo.setCategoryRotation(
                                c,
                                value,
                              );
                              if (context.mounted) reportCare(context, r);
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}
