import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../l10n/app_localizations.dart';
import '../../care/application/care_providers.dart';
import '../../wardrobe/domain/garment.dart';
import '../../wardrobe/presentation/garment_photo_view.dart';
import '../../wear/presentation/today_wear_card.dart';
import '../application/outfit_providers.dart';
import '../domain/outfit.dart';
import 'outfit_messages.dart';

class OutfitsScreen extends ConsumerWidget {
  const OutfitsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final outfits = ref.watch(outfitsProvider);
    final garments = ref.watch(allGarmentsProvider).value;
    final ready = ref.watch(outfitRepositoryProvider) != null;

    final Widget body = switch (outfits) {
      AsyncData(value: final list) when list.isEmpty => EmptyState(
        icon: Icons.style_outlined,
        message: l10n.outfitsEmpty,
        hint: l10n.outfitsEmptyHint,
      ),
      AsyncData(value: final list) => ListView(
        padding: const EdgeInsets.only(bottom: 88),
        children: [
          for (final o in list)
            _OutfitTile(
              outfit: o,
              garments: {
                for (final g in garments ?? const <Garment>[]) g.id: g,
              },
            ),
        ],
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
}

class _OutfitTile extends StatelessWidget {
  const _OutfitTile({required this.outfit, required this.garments});

  final Outfit outfit;
  final Map<GarmentId, Garment> garments;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final pieces = [for (final i in outfit.items) garments[i.garmentId]];
    final unavailable = pieces.where((g) => pieceWarning(l10n, g) != null);
    final title =
        outfit.name ??
        pieces.take(3).map((g) => garmentLabel(l10n, g)).join(' + ');
    final details = [
      l10n.outfitPiecesCount(outfit.items.length),
      for (final o in outfit.occasions) l10n.occasionLabel(o.id),
      if (OutfitRules.missing(outfit.items).isNotEmpty) l10n.outfitIncomplete,
    ];
    final cover = pieces.whereType<Garment>().where((g) => g.photos.isNotEmpty);

    return ListTile(
      key: Key('outfit-${outfit.id}'),
      leading: cover.isEmpty
          ? const SizedBox.square(
              dimension: 48,
              child: Icon(Icons.style_outlined),
            )
          : GarmentPhotoView(photo: cover.first.photos.first, size: 48),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          details.join(' · '),
          if (unavailable.isNotEmpty)
            l10n.outfitUnavailable(unavailable.length),
        ].join('\n'),
      ),
      isThreeLine: unavailable.isNotEmpty,
      trailing: unavailable.isEmpty
          ? null
          : Icon(
              Icons.warning_amber_outlined,
              color: Theme.of(context).colorScheme.error,
            ),
      onTap: () => context.push(AppRoutes.outfit(outfit.id)),
    );
  }
}
