import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/router.dart';
import '../../../app/theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../care/application/care_providers.dart';
import '../../care/domain/laundry_basket.dart';
import '../../engine/presentation/today_suggestions_card.dart';
import '../../wear/application/wear_providers.dart';
import '../../wear/presentation/today_wear_card.dart';

/// "Hoje" (design do Stitch): a data e uma saudação, o tempo, o look do
/// dia num cartão, atalhos, a lavandaria e o que já vestiste. A semana
/// tem separador próprio ([WeekScreen]).
class PlannerScreen extends StatelessWidget {
  const PlannerScreen({super.key});

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
    children: const [
      _Greeting(),
      SizedBox(height: 12),
      TodaySuggestionsCard(),
      SizedBox(height: 16),
      _QuickActions(),
      _LaundryCard(),
      SizedBox(height: 28),
      TodayWearCard(),
    ],
  );
}

class _Greeting extends ConsumerWidget {
  const _Greeting();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final now = ref.watch(clockProvider).nowUtc().toLocal();
    final part = switch (now.hour) {
      >= 5 && < 12 => 'morning',
      >= 12 && < 20 => 'afternoon',
      _ => 'night',
    };
    final locale = Localizations.localeOf(context).toLanguageTag();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          DateFormat.MMMMEEEEd(locale).format(now).toUpperCase(),
          key: const Key('today-date'),
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            letterSpacing: 0.8,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          AppLocalizations.of(context).todayGreeting(part),
          key: const Key('today-greeting'),
          style: theme.textTheme.displaySmall,
        ),
      ],
    );
  }
}

/// Três atalhos: peça nova, conjunto novo e a semana.
class _QuickActions extends StatelessWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Os três com a mesma altura, mesmo que um nome ocupe duas linhas.
    return IntrinsicHeight(
      child: Row(
        spacing: 10,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (key, icon, label, go) in [
            (
              'quick-add-garment',
              Icons.add,
              l10n.wardrobeAdd,
              () => context.push(AppRoutes.newGarment),
            ),
            (
              'quick-new-outfit',
              Icons.style_outlined,
              l10n.outfitsAdd,
              () => context.push(AppRoutes.newOutfit),
            ),
            (
              'quick-week',
              Icons.calendar_month_outlined,
              l10n.todayPlanWeek,
              () => context.go(AppRoutes.week),
            ),
          ])
            Expanded(
              child: _QuickAction(
                key: Key(key),
                icon: icon,
                label: label,
                onTap: go,
              ),
            ),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 14, 8, 12),
          child: Column(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: colors.accentSoft,
                foregroundColor: colors.onAccentSoft,
                child: Icon(icon),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                maxLines: 2,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelLarge
                    ?.copyWith(fontSize: 13, height: 1.2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Só com peças por lavar, a lavar, a secar ou na limpeza: quantas são,
/// as primeiras pelo nome e "Ver" para o cesto.
class _LaundryCard extends ConsumerWidget {
  const _LaundryCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final basket = LaundryBasket.of(
      ref.watch(allGarmentsProvider).value ?? const [],
    );
    if (basket.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final garments = [
      for (final load in basket.loads) ...load.garments,
      ...basket.inProgress,
      ...basket.atCleaners,
    ];
    const shown = 3;
    final names = [
      for (final g in garments.take(shown)) garmentLabel(l10n, g),
      if (garments.length > shown) '…',
    ].join(', ');
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Card(
        key: const Key('today-laundry'),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push(AppRoutes.laundryBasket),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: colors.care.withValues(alpha: 0.28),
                  foregroundColor: colors.onCareSoft,
                  child: const Icon(Icons.local_laundry_service_outlined),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.todayLaundry(basket.count),
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: colors.onCareSoft,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        names,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colors.onSurfaceMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => context.push(AppRoutes.laundryBasket),
                  child: Text(l10n.todayLaundryOpen),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
