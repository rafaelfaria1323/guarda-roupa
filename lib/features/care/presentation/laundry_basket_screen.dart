import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../app/theme.dart';
import '../../../core/domain/result.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../l10n/app_localizations.dart';
import '../../account_sync/application/providers.dart';
import '../../wardrobe/domain/availability.dart';
import '../../wardrobe/domain/garment.dart';
import '../../wardrobe/domain/garment_photo.dart';
import '../../wardrobe/presentation/garment_cutout.dart';
import '../../wear/application/wear_providers.dart';
import '../application/care_providers.dart';
import '../domain/cleaning_event.dart';
import '../domain/laundry_basket.dart';

/// Cesto da roupa: o que está por lavar, junto por máquina (lavagem e
/// tom), o que está a lavar ou a secar e o que está na lavandaria. Cada
/// grupo resolve-se de uma vez, com "Desfazer".
class LaundryBasketScreen extends ConsumerWidget {
  const LaundryBasketScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final garments = ref.watch(allGarmentsProvider).value;
    final basket = garments == null ? null : LaundryBasket.of(garments);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.basketTitle)),
      body: basket == null
          ? const Center(child: CircularProgressIndicator())
          : basket.isEmpty
          ? EmptyState(
              icon: Icons.local_laundry_service_outlined,
              message: l10n.basketEmpty,
              hint: l10n.basketEmptyHint,
            )
          : ListView(
              key: const Key('basket-list'),
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                _Stats(basket: basket),
                if (basket.loads.isNotEmpty) _Heading(l10n.basketDirty),
                for (final load in basket.loads)
                  _Group(
                    key: Key(
                      'basket-load-${load.program.id}'
                      '${load.shade == null ? '' : '-${load.shade!.id}'}',
                    ),
                    title: load.shade == null
                        ? l10n.washProgramLabel(load.program.id)
                        : l10n.basketLoad(
                            l10n.washProgramLabel(load.program.id),
                            l10n.shadeLabel(load.shade!.id),
                          ),
                    hint: load.program == WashProgram.unknown
                        ? l10n.basketUnknownHint
                        : null,
                    garments: load.garments,
                    action: load.program == WashProgram.professional
                        ? _Action(
                            Icons.dry_cleaning_outlined,
                            l10n.basketToCleaners,
                            (c) => _toCleaners(c, ref, load.garments),
                          )
                        : _Action(
                            Icons.local_laundry_service_outlined,
                            l10n.basketWashed,
                            (c) => _cleaned(c, ref, load.garments),
                          ),
                  ),
                if (basket.inProgress.isNotEmpty)
                  _Group(
                    key: const Key('basket-in-progress'),
                    heading: true,
                    title: l10n.basketInProgress,
                    garments: basket.inProgress,
                    action: _Action(
                      Icons.check,
                      l10n.basketReady,
                      (c) => _cleaned(c, ref, basket.inProgress),
                    ),
                  ),
                if (basket.atCleaners.isNotEmpty)
                  _Group(
                    key: const Key('basket-at-cleaners'),
                    heading: true,
                    title: l10n.basketAtCleaners,
                    garments: basket.atCleaners,
                    action: _Action(
                      Icons.dry_cleaning_outlined,
                      l10n.basketBack,
                      (c) => _cleaned(c, ref, basket.atCleaners),
                    ),
                  ),
              ],
            ),
    );
  }

  /// Lavadas hoje e disponíveis outra vez (como "Lavei hoje" na ficha).
  Future<void> _cleaned(
    BuildContext context,
    WidgetRef ref,
    List<Garment> garments,
  ) async {
    final care = ref.read(careRepositoryProvider);
    final wardrobe = ref.read(wardrobeRepositoryProvider);
    if (care == null || wardrobe == null) return;
    // O grupo desaparece quando as peças saem dele: guardar já o
    // messenger para o aviso com "Desfazer".
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    final today = todayFrom(ref.read(clockProvider));
    final events = <CleaningEvent>[];
    final restored = <(Garment, Availability)>[];
    for (final g in garments) {
      final r = await care.recordCleaning(g.id, today);
      if (r case Ok(:final value)) events.add(value);
      if (await wardrobe.setAvailability(g.id, Availability.available) is Ok) {
        restored.add((g, g.availability));
      }
    }
    _snack(
      messenger,
      l10n,
      l10n.basketAvailableAgain(restored.length),
      () async {
        for (final e in events) {
          await care.voidCleaning(e.id);
        }
        for (final (g, before) in restored) {
          await wardrobe.setAvailability(g.id, before);
        }
      },
    );
  }

  Future<void> _toCleaners(
    BuildContext context,
    WidgetRef ref,
    List<Garment> garments,
  ) async {
    final wardrobe = ref.read(wardrobeRepositoryProvider);
    if (wardrobe == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    final moved = <(Garment, Availability)>[];
    for (final g in garments) {
      if (await wardrobe.setAvailability(g.id, Availability.atCleaners) is Ok) {
        moved.add((g, g.availability));
      }
    }
    _snack(messenger, l10n, l10n.basketSentToCleaners(moved.length), () async {
      for (final (g, before) in moved) {
        await wardrobe.setAvailability(g.id, before);
      }
    });
  }

  void _snack(
    ScaffoldMessengerState messenger,
    AppLocalizations l10n,
    String text,
    VoidCallback undo,
  ) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(text),
          action: SnackBarAction(label: l10n.wearUndo, onPressed: undo),
        ),
      );
  }
}

class _Action {
  const _Action(this.icon, this.label, this.run);

  final IconData icon;
  final String label;
  final Future<void> Function(BuildContext) run;
}

/// Os três números do cesto: por lavar, a lavar ou a secar, na lavandaria.
class _Stats extends StatelessWidget {
  const _Stats({required this.basket});

  final LaundryBasket basket;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final dirty = basket.loads.fold(0, (n, l) => n + l.garments.length);
    return IntrinsicHeight(
      child: Row(
        spacing: 8,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Stat(
            key: const Key('basket-stat-dirty'),
            icon: Icons.inventory_2_outlined,
            value: dirty,
            label: l10n.basketDirty,
            highlight: dirty > 0,
          ),
          _Stat(
            key: const Key('basket-stat-in-progress'),
            icon: Icons.local_laundry_service_outlined,
            value: basket.inProgress.length,
            label: l10n.basketInProgress,
          ),
          _Stat(
            key: const Key('basket-stat-at-cleaners'),
            icon: Icons.dry_cleaning_outlined,
            value: basket.atCleaners.length,
            label: l10n.basketAtCleaners,
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.icon,
    required this.value,
    required this.label,
    this.highlight = false,
    super.key,
  });

  final IconData icon;
  final int value;
  final String label;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    return Expanded(
      child: Card(
        margin: EdgeInsets.zero,
        color: highlight ? colors.care.withValues(alpha: 0.14) : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                icon,
                size: 20,
                color: highlight ? colors.onCareSoft : colors.onSurfaceMuted,
              ),
              const SizedBox(height: 8),
              Text(
                '$value',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: highlight ? colors.onCareSoft : null,
                ),
              ),
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: highlight ? colors.onCareSoft : colors.onSurfaceMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 24, 4, 0),
    child: Text(text, style: Theme.of(context).textTheme.titleLarge),
  );
}

class _Group extends StatelessWidget {
  const _Group({
    required this.title,
    required this.garments,
    required this.action,
    this.hint,
    this.heading = false,
    super.key,
  });

  final String title;
  final String? hint;
  final List<Garment> garments;
  final _Action action;

  /// Secção própria (título maior), e não uma máquina dentro de "Para lavar".
  final bool heading;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final id = (key as ValueKey<String>?)?.value;
    final header = Row(
      children: [
        Flexible(
          child: Text(
            title,
            style: heading
                ? theme.textTheme.titleLarge
                : theme.textTheme.titleMedium,
          ),
        ),
        const SizedBox(width: 8),
        DecoratedBox(
          decoration: BoxDecoration(
            color: colors.accentSoft,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
            child: Text(
              '${garments.length}',
              key: Key('$id-count'),
              style: theme.textTheme.labelMedium?.copyWith(
                color: colors.accent,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
    return Padding(
      padding: EdgeInsets.only(top: heading ? 24 : 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (heading) ...[
            Padding(padding: const EdgeInsets.only(left: 4), child: header),
            const SizedBox(height: 8),
          ],
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!heading) header,
                  if (hint != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        hint!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceMuted,
                        ),
                      ),
                    ),
                  if (!heading || hint != null) const SizedBox(height: 4),
                  for (final (i, g) in garments.indexed) ...[
                    if (i > 0) Divider(height: 1, color: colors.outline),
                    InkWell(
                      key: Key('basket-garment-${g.id.value}'),
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => context.push(AppRoutes.garment(g.id)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: ColoredBox(
                                color: colors.surfaceMuted,
                                child: SizedBox.square(
                                  dimension: 64,
                                  child: Center(
                                    child: GarmentCutout(
                                      garment: g,
                                      size: 48,
                                      variant: PhotoVariant.thumb,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    l10n
                                        .categoryLabel(g.category.id)
                                        .toUpperCase(),
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: colors.onSurfaceMuted,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    g.name ?? l10n.categoryLabel(g.category.id),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.titleSmall,
                                  ),
                                  if (g.attributes.material case final m?)
                                    Text(
                                      m,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: colors.onSurfaceMuted,
                                          ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            DecoratedBox(
                              decoration: BoxDecoration(
                                color: colors.care.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                child: Text(
                                  l10n.availabilityLabel(g.availability.id),
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: colors.onCareSoft,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.tonalIcon(
                      key: Key('$id-action'),
                      icon: Icon(action.icon),
                      label: Text(action.label),
                      onPressed: () => action.run(context),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
