import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/domain/result.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../l10n/app_localizations.dart';
import '../../account_sync/application/providers.dart';
import '../../wardrobe/domain/availability.dart';
import '../../wardrobe/domain/garment.dart';
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
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
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

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 16, 4, 4),
    child: Text(text, style: Theme.of(context).textTheme.titleMedium),
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
    return Padding(
      padding: EdgeInsets.only(top: heading ? 16 : 8),
      child: Card.outlined(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$title · ${garments.length}',
                style: heading
                    ? theme.textTheme.titleMedium
                    : theme.textTheme.titleSmall,
              ),
              if (hint != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    hint!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final g in garments)
                    InkWell(
                      key: Key('basket-garment-${g.id.value}'),
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => context.push(AppRoutes.garment(g.id)),
                      child: SizedBox(
                        width: 72,
                        child: Column(
                          children: [
                            GarmentCutout(garment: g, size: 64),
                            const SizedBox(height: 4),
                            Text(
                              g.name ?? l10n.categoryLabel(g.category.id),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonalIcon(
                  key: Key('${(key as ValueKey<String>?)?.value}-action'),
                  icon: Icon(action.icon),
                  label: Text(action.label),
                  onPressed: () => action.run(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
