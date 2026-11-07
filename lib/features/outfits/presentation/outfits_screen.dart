import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../app/theme.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../l10n/app_localizations.dart';
import '../../care/application/care_providers.dart';
import '../../wardrobe/domain/garment.dart';
import '../../wardrobe/domain/garment_attributes.dart';
import '../../wardrobe/domain/garment_photo.dart';
import '../../wardrobe/presentation/garment_cutout.dart';
import '../../wear/application/wear_providers.dart';
import '../../wear/domain/calendar_day.dart';
import '../../wear/domain/wear_event.dart';
import '../../wear/presentation/today_wear_card.dart';
import '../application/outfit_providers.dart';
import '../domain/outfit.dart';
import 'outfit_messages.dart';

/// Os conjuntos guardados como cartões, com as peças em colagem, quantas
/// vezes já foram usados e "Vou vestir hoje" à mão.
class OutfitsScreen extends ConsumerStatefulWidget {
  const OutfitsScreen({super.key});

  @override
  ConsumerState<OutfitsScreen> createState() => _OutfitsScreenState();
}

class _OutfitsScreenState extends ConsumerState<OutfitsScreen> {
  Occasion? _occasion;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final outfits = ref.watch(outfitsProvider);
    final garments = {
      for (final g in ref.watch(allGarmentsProvider).value ?? const <Garment>[])
        g.id: g,
    };
    final wears = ref.watch(allWearsProvider).value ?? const <WearEvent>[];
    final today = todayFrom(ref.watch(clockProvider));
    final ready = ref.watch(outfitRepositoryProvider) != null;

    final Widget body = switch (outfits) {
      AsyncData(value: final list) when list.isEmpty => EmptyState(
        icon: Icons.style_outlined,
        message: l10n.outfitsEmpty,
        hint: l10n.outfitsEmptyHint,
      ),
      AsyncData(value: final list) => _list(
        context,
        list,
        garments,
        wears,
        today,
      ),
      AsyncError() => Center(child: Text(l10n.wardrobeLoadError)),
      _ => const Center(child: CircularProgressIndicator()),
    };

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        // Os separadores ficam montados lado a lado: sem Hero partilhado.
        heroTag: null,
        key: const Key('outfit-add'),
        onPressed: ready ? () => context.push(AppRoutes.newOutfit) : null,
        icon: const Icon(Icons.add),
        label: Text(l10n.outfitsAdd),
      ),
      body: body,
    );
  }

  Widget _list(
    BuildContext context,
    List<Outfit> all,
    Map<GarmentId, Garment> garments,
    List<WearEvent> wears,
    CalendarDay today,
  ) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final byOccasion = <Occasion, int>{};
    for (final o in all) {
      for (final occasion in o.occasions) {
        byOccasion[occasion] = (byOccasion[occasion] ?? 0) + 1;
      }
    }
    final shown = [
      for (final o in all)
        if (_occasion == null || o.occasions.contains(_occasion)) o,
    ];
    return ListView(
      padding: const EdgeInsets.only(bottom: 96),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
          child: Text(
            l10n.outfitsSaved(all.length),
            key: const Key('outfits-count'),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.of(context).onSurfaceMuted,
            ),
          ),
        ),
        if (byOccasion.isNotEmpty)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            child: Row(
              spacing: 8,
              children: [
                FilterChip(
                  key: const Key('outfits-filter-all'),
                  showCheckmark: false,
                  label: Text(
                    l10n.wardrobeGroupCount(
                      l10n.outfitsAllOccasions,
                      all.length,
                    ),
                  ),
                  selected: _occasion == null,
                  onSelected: (_) => setState(() => _occasion = null),
                ),
                for (final occasion in Occasion.values)
                  if (byOccasion[occasion] case final n?)
                    FilterChip(
                      key: Key('outfits-filter-${occasion.id}'),
                      showCheckmark: false,
                      label: Text(
                        l10n.wardrobeGroupCount(
                          l10n.occasionLabel(occasion.id),
                          n,
                        ),
                      ),
                      selected: _occasion == occasion,
                      onSelected: (on) =>
                          setState(() => _occasion = on ? occasion : null),
                    ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              children: [
                for (final o in shown)
                  _OutfitCard(
                    outfit: o,
                    garments: garments,
                    wears: wears,
                    today: today,
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _OutfitCard extends StatelessWidget {
  const _OutfitCard({
    required this.outfit,
    required this.garments,
    required this.wears,
    required this.today,
  });

  final Outfit outfit;
  final Map<GarmentId, Garment> garments;
  final List<WearEvent> wears;
  final CalendarDay today;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final pieces = [for (final i in outfit.items) garments[i.garmentId]];
    final present = pieces.whereType<Garment>().toList();
    final unavailable = pieces.where((g) => pieceWarning(l10n, g) != null);
    final title =
        outfit.name ??
        pieces.take(3).map((g) => garmentLabel(l10n, g)).join(' + ');
    final names = pieces.map((g) => garmentLabel(l10n, g)).join(' + ');

    // Usado quando todas as peças do conjunto foram vestidas no mesmo dia.
    final ids = {for (final i in outfit.items) i.garmentId};
    final worn = [
      for (final w in wears)
        if (ids.isNotEmpty && w.garmentIds.toSet().containsAll(ids)) w,
    ]..sort((a, b) => b.wornOn.compareTo(a.wornOn));
    final meta = [
      l10n.outfitWorn(worn.length),
      if (worn.isNotEmpty) l10n.relativeDay(worn.first.wornOn.daysUntil(today)),
      if (OutfitRules.missing(outfit.items).isNotEmpty) l10n.outfitIncomplete,
    ].join(' · ');
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: colors.onSurfaceMuted,
    );

    return Card(
      key: Key('outfit-${outfit.id}'),
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push(AppRoutes.outfit(outfit.id)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 16 / 10,
              child: Stack(
                children: [
                  Positioned.fill(child: _Collage(pieces: present)),
                  Positioned(
                    top: 10,
                    left: 10,
                    child: _Badge(
                      key: const Key('outfit-pieces'),
                      text: l10n.outfitPiecesCount(outfit.items.length),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                      if (outfit.occasions.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        _Badge(
                          text: outfit.occasions
                              .map((o) => l10n.occasionLabel(o.id))
                              .join(' · '),
                          muted: true,
                        ),
                      ],
                    ],
                  ),
                  if (outfit.name != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      names,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: muted,
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(meta, key: const Key('outfit-worn'), style: muted),
                  if (unavailable.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.warning_amber_outlined,
                          size: 16,
                          color: colors.care,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            l10n.outfitUnavailable(unavailable.length),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.care,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 14),
                  Row(
                    spacing: 8,
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          key: Key('outfit-wear-${outfit.id}'),
                          onPressed: present.isEmpty
                              ? null
                              : () => context.push(
                                  AppRoutes.wearWith([
                                    for (final g in present) g.id.value,
                                  ]),
                                ),
                          icon: const Icon(Icons.done_all),
                          label: Text(l10n.garmentWearToday),
                        ),
                      ),
                      FilledButton.tonalIcon(
                        key: Key('outfit-edit-${outfit.id}'),
                        onPressed: () =>
                            context.push(AppRoutes.outfit(outfit.id)),
                        icon: const Icon(Icons.edit_outlined),
                        label: Text(l10n.outfitEditAction),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Até três peças: a primeira em grande à esquerda, as outras empilhadas.
class _Collage extends StatelessWidget {
  const _Collage({required this.pieces});

  final List<Garment> pieces;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    Widget cell(Garment? g, double angle) => ColoredBox(
      color: colors.surfaceMuted,
      child: g == null
          ? const SizedBox.expand()
          : LayoutBuilder(
              builder: (context, box) => Center(
                child: GarmentCutout(
                  garment: g,
                  size: box.biggest.shortestSide * 0.66,
                  angle: angle,
                  variant: PhotoVariant.thumb,
                ),
              ),
            ),
    );
    if (pieces.isEmpty) {
      return ColoredBox(
        color: colors.surfaceMuted,
        child: Icon(Icons.style_outlined, color: colors.onSurfaceMuted),
      );
    }
    if (pieces.length == 1) return cell(pieces.first, -0.03);
    return Row(
      spacing: 3,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(flex: 3, child: cell(pieces[0], -0.03)),
        Expanded(
          flex: 2,
          child: Column(
            spacing: 3,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: cell(pieces[1], 0.04)),
              if (pieces.length > 2) Expanded(child: cell(pieces[2], -0.05)),
            ],
          ),
        ),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, this.muted = false, super.key});

  final String text;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: muted
            ? colors.surfaceMuted
            : theme.colorScheme.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Text(
          text,
          style: theme.textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
