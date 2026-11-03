import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/domain/result.dart';
import '../../../l10n/app_localizations.dart';
import '../../account_sync/application/providers.dart';
import '../../wardrobe/domain/garment.dart';
import '../../wardrobe/domain/garment_filter.dart';
import '../../wardrobe/presentation/garment_photo_view.dart';
import '../../care/application/care_providers.dart';
import '../../care/domain/rotation_policy.dart';
import '../../outfits/application/outfit_providers.dart';
import '../../outfits/domain/outfit.dart';
import '../application/wear_providers.dart';
import '../domain/wear_event.dart';
import '../domain/wear_repository.dart';
import 'today_wear_card.dart';
import 'wear_messages.dart';

/// Escolher as peças vestidas hoje (`eventId == null`) ou corrigir as de
/// uma utilização já registada.
class WearPickerScreen extends ConsumerStatefulWidget {
  const WearPickerScreen({this.eventId, super.key});

  final String? eventId;

  @override
  ConsumerState<WearPickerScreen> createState() => _WearPickerScreenState();
}

class _WearPickerScreenState extends ConsumerState<WearPickerScreen> {
  final _selected = <GarmentId>{};
  bool _loaded = false;
  bool _saving = false;
  Stream<List<Garment>>? _garments;
  Stream<WearEvent?>? _event;

  bool get _correcting => widget.eventId != null;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final wardrobe = ref.watch(wardrobeRepositoryProvider);
    final repo = ref.watch(wearRepositoryProvider);
    if (wardrobe == null || repo == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    _garments ??= wardrobe.watchGarments(const GarmentFilter());
    if (widget.eventId case final id?) _event ??= repo.watchEvent(id);

    return Scaffold(
      appBar: AppBar(
        title: Text(_correcting ? l10n.wearCorrectTitle : l10n.wearPickTitle),
        actions: [
          TextButton(
            key: const Key('wear-save'),
            onPressed: _saving || _selected.isEmpty || !_ready
                ? null
                : () => _save(repo),
            child: Text(l10n.wearSave),
          ),
        ],
      ),
      body: StreamBuilder<WearEvent?>(
        stream: _event,
        builder: (context, event) {
          if (_correcting && !_loaded) {
            if (event.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final current = event.data;
            if (current == null) return Center(child: Text(l10n.wearNotFound));
            _selected.addAll(current.garmentIds);
            _loaded = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() {});
            });
          }
          return _list(context);
        },
      ),
    );
  }

  bool get _ready => !_correcting || _loaded;

  Widget _list(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final rotation = ref.watch(rotationStatesProvider);
    final outfits = ref.watch(outfitsProvider).value ?? const <Outfit>[];
    return StreamBuilder<List<Garment>>(
      stream: _garments,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text(l10n.wardrobeLoadError));
        }
        final garments = snapshot.data;
        if (garments == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (garments.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(l10n.wearPickEmpty, textAlign: TextAlign.center),
            ),
          );
        }
        final sorted = [...garments]
          ..sort((a, b) {
            final byCategory = a.category.index.compareTo(b.category.index);
            if (byCategory != 0) return byCategory;
            return (a.name ?? '').compareTo(b.name ?? '');
          });
        return ListView(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(l10n.wearPickHint),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.wearSelected(_selected.length),
                      key: const Key('wear-selected'),
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                  if (outfits.isNotEmpty)
                    TextButton.icon(
                      key: const Key('wear-from-outfit'),
                      onPressed: () => _pickOutfit(outfits, garments),
                      icon: const Icon(Icons.style_outlined),
                      label: Text(l10n.wearFromOutfit),
                    ),
                ],
              ),
            ),
            for (final g in sorted)
              CheckboxListTile(
                key: Key('wear-pick-${g.id.value}'),
                value: _selected.contains(g.id),
                onChanged: (on) => setState(
                  () =>
                      on == true ? _selected.add(g.id) : _selected.remove(g.id),
                ),
                title: Text(garmentLabel(l10n, g)),
                subtitle: _subtitle(l10n, g, rotation?[g.id]),
                secondary: g.photos.isEmpty
                    ? const SizedBox.square(
                        dimension: 40,
                        child: Icon(Icons.checkroom_outlined),
                      )
                    : GarmentPhotoView(photo: g.photos.first, size: 40),
              ),
          ],
        );
      },
    );
  }

  /// Marca as peças de um conjunto guardado (substitui a seleção). Peças
  /// que já não existem ficam de fora, com aviso; o utilizador ajusta antes
  /// de guardar.
  Future<void> _pickOutfit(List<Outfit> outfits, List<Garment> garments) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final byId = {for (final g in garments) g.id: g};
    final chosen = await showModalBottomSheet<Outfit>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: Text(
                l10n.wearFromOutfitTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            for (final o in outfits)
              ListTile(
                key: Key('wear-outfit-${o.id}'),
                title: Text(
                  o.name ??
                      o.items
                          .take(3)
                          .map((i) => garmentLabel(l10n, byId[i.garmentId]))
                          .join(' + '),
                ),
                subtitle: Text(l10n.outfitPiecesCount(o.items.length)),
                onTap: () => Navigator.pop(context, o),
              ),
          ],
        ),
      ),
    );
    if (chosen == null || !mounted) return;
    final present = [
      for (final i in chosen.items)
        if (byId.containsKey(i.garmentId)) i.garmentId,
    ];
    setState(
      () => _selected
        ..clear()
        ..addAll(present),
    );
    final skipped = chosen.items.length - present.length;
    if (skipped > 0) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(l10n.wearFromOutfitSkipped(skipped))),
        );
    }
  }

  /// Só informativo: o registo é do que aconteceu, não uma sugestão.
  static Widget? _subtitle(
    AppLocalizations l10n,
    Garment g,
    RotationState? rotation,
  ) {
    final from = rotation?.eligibleFrom;
    final lines = [
      if (g.name != null) l10n.categoryLabel(g.category.id),
      if (from != null) l10n.rotationPickHint(from.toLocalDateTime()),
    ];
    return lines.isEmpty ? null : Text(lines.join('\n'));
  }

  Future<void> _save(WearRepository repo) async {
    setState(() => _saving = true);
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final WearResult<WearEvent> result = switch (widget.eventId) {
      final id? => await repo.correctWear(id, _selected),
      null => await repo.recordWear(
        todayFrom(ref.read(clockProvider)),
        _selected,
      ),
    };
    if (!mounted) return;
    setState(() => _saving = false);
    if (!reportWear(context, result)) return;
    final event = (result as Ok<WearEvent, WearFailure>).value;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(_correcting ? l10n.wearCorrected : l10n.wearRecorded),
          action: _correcting
              ? null
              : SnackBarAction(
                  label: l10n.wearUndo,
                  onPressed: () => repo.voidWear(event.id),
                ),
        ),
      );
    context.pop();
  }
}
