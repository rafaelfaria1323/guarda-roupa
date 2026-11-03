import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../wardrobe/domain/garment_category.dart';
import '../application/care_providers.dart';
import '../domain/laundry_policy.dart';
import 'care_messages.dart';
import 'laundry_after_field.dart';

/// Aviso de lavagem por categoria (P-07). Cada peça pode ter o seu.
class CareSettingsScreen extends ConsumerWidget {
  const CareSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final policies = ref.watch(carePoliciesProvider).value;
    final repo = ref.watch(careRepositoryProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.careSettingsTitle)),
      body: policies == null || repo == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(l10n.careSettingsHint),
                const SizedBox(height: 16),
                for (final c in GarmentCategory.values)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: LaundryAfterField(
                      key: ValueKey(
                        'laundry-category-${c.id}-'
                        '${policies.laundryByCategory[c]}',
                      ),
                      label: l10n.categoryLabel(c.id),
                      value: policies.laundryByCategory[c],
                      defaultValue: LaundryPolicy.defaultFor(c),
                      onChanged: (value) async {
                        final r = await repo.setCategoryLaundry(c, value);
                        if (context.mounted) reportCare(context, r);
                      },
                    ),
                  ),
              ],
            ),
    );
  }
}
