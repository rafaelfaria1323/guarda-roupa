import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../l10n/app_localizations.dart';
import '../../care/application/care_providers.dart';
import '../../wardrobe/presentation/garment_cutout.dart';
import '../application/wear_providers.dart';
import '../domain/calendar_day.dart';
import '../domain/wardrobe_insights.dart';

/// Resumo do armário: o que mais usas, o que está parado e o que nunca
/// usaste. Cada peça abre a ficha (onde se arquiva ou se marca para usar).
class WardrobeInsightsScreen extends ConsumerWidget {
  const WardrobeInsightsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final garments = ref.watch(allGarmentsProvider).value;
    final wears = ref.watch(allWearsProvider).value;
    final today = todayFrom(ref.watch(clockProvider));
    final insights = garments == null || wears == null
        ? null
        : WardrobeInsights.of(garments, wears, today);
    final material = MaterialLocalizations.of(context);
    String date(CalendarDay d) => material.formatShortDate(d.toLocalDateTime());

    return Scaffold(
      appBar: AppBar(title: Text(l10n.insightsTitle)),
      body: switch (insights) {
        null => const Center(child: CircularProgressIndicator()),
        WardrobeInsights(hasHistory: false, neverWorn: [], fresh: _) =>
          EmptyState(
            key: const Key('insights-empty'),
            icon: Icons.insights_outlined,
            message: l10n.insightsNoHistory,
            hint: l10n.insightsNoHistoryHint,
          ),
        final i => ListView(
          key: const Key('insights-list'),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Text(
              l10n.insightsWorn(
                i.wornRecently,
                i.active,
                WardrobeInsights.recentDays,
              ),
              key: const Key('insights-worn'),
              style: theme.textTheme.bodyLarge,
            ),
            if (!i.hasHistory)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  l10n.insightsNoHistoryHint,
                  style: theme.textTheme.bodySmall,
                ),
              ),
            if (i.mostWorn.isNotEmpty)
              _Section(
                id: 'most',
                title: l10n.insightsMostWorn,
                hint: l10n.insightsMostWornHint(WardrobeInsights.recentDays),
                items: [
                  for (final u in i.mostWorn)
                    (u, l10n.insightsTimes(u.recentUses)),
                ],
              ),
            if (i.idle.isNotEmpty)
              _Section(
                id: 'idle',
                title: l10n.insightsIdle,
                hint: l10n.insightsIdleHint(WardrobeInsights.idleAfterDays),
                items: [
                  for (final u in i.idle)
                    (u, l10n.insightsDaysAgo(u.lastWornOn!.daysUntil(today))),
                ],
              ),
            if (i.neverWorn.isNotEmpty)
              _Section(
                id: 'never',
                title: l10n.insightsNever,
                hint: l10n.insightsNeverHint(WardrobeInsights.freshForDays),
                items: [
                  for (final u in i.neverWorn)
                    (
                      u,
                      l10n.insightsSince(
                        date(CalendarDay.of(u.garment.createdAt)),
                      ),
                    ),
                ],
              ),
            if (i.fresh > 0)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(
                  l10n.insightsFresh(i.fresh),
                  key: const Key('insights-fresh'),
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            if (i.hasHistory && i.idle.isEmpty && i.neverWorn.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(
                  l10n.insightsAllGood,
                  key: const Key('insights-all-good'),
                  style: theme.textTheme.bodyMedium,
                ),
              ),
          ],
        ),
      },
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.id,
    required this.title,
    required this.hint,
    required this.items,
  });

  final String id;
  final String title;
  final String hint;
  final List<(GarmentUse, String)> items;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Padding(
      key: Key('insights-$id'),
      padding: const EdgeInsets.only(top: 16),
      child: Card.outlined(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$title · ${items.length}',
                style: theme.textTheme.titleMedium,
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 8),
                child: Text(
                  hint,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (u, detail) in items)
                    InkWell(
                      key: Key('insights-$id-${u.garment.id.value}'),
                      borderRadius: BorderRadius.circular(8),
                      onTap: () =>
                          context.push(AppRoutes.garment(u.garment.id)),
                      child: SizedBox(
                        width: 80,
                        child: Column(
                          children: [
                            GarmentCutout(garment: u.garment, size: 64),
                            const SizedBox(height: 4),
                            Text(
                              u.garment.name ??
                                  l10n.categoryLabel(u.garment.category.id),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall,
                            ),
                            Text(
                              detail,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
