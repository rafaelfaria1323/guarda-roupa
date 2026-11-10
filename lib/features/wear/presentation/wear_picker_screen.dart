import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/domain/result.dart';
import '../../../l10n/app_localizations.dart';
import '../../account_sync/application/providers.dart';
import '../../wardrobe/domain/availability.dart';
import '../../wardrobe/domain/garment.dart';
import '../../wardrobe/domain/garment_filter.dart';
import '../../wardrobe/domain/garment_twins.dart';
import '../../wardrobe/presentation/garment_photo_view.dart';
import '../../care/application/care_providers.dart';
import '../../care/domain/laundry_policy.dart';
import '../../care/domain/rotation_policy.dart';
import '../../outfits/application/outfit_providers.dart';
import '../../outfits/domain/outfit.dart';
import '../application/wear_providers.dart';
import '../domain/calendar_day.dart';
import '../domain/wear_event.dart';
import '../domain/wear_repository.dart';
import 'today_wear_card.dart';
import 'wear_messages.dart';

/// Escolher as peças vestidas hoje (`eventId == null`) ou corrigir as de
/// uma utilização já registada.
class WearPickerScreen extends ConsumerStatefulWidget {
  const WearPickerScreen({
    this.eventId,
    this.initial = const [],
    this.planEntryId,
    super.key,
  });

  final String? eventId;

  /// Peças já escolhidas ao abrir (ex.: uma sugestão). O utilizador
  /// confirma ou muda antes de guardar; nada conta como uso até guardar.
  final List<GarmentId> initial;

  /// Entrada do plano que esta utilização confirma (só ao registar).
  final String? planEntryId;

  @override
  ConsumerState<WearPickerScreen> createState() => _WearPickerScreenState();
}

class _WearPickerScreenState extends ConsumerState<WearPickerScreen> {
  final _selected = <GarmentId>{};

  /// Peças que ficaram para lavar já (nódoa, suor, uso intenso), mesmo
  /// antes do limiar. Só contam as que continuam escolhidas.
  final _dirtyNow = <GarmentId>{};
  bool _loaded = false;
  bool _saving = false;
  Stream<List<Garment>>? _garments;
  Stream<WearEvent?>? _event;

  bool get _correcting => widget.eventId != null;

  @override
  void initState() {
    super.initState();
    if (!_correcting) _selected.addAll(widget.initial);
  }

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
    final lastWorn = ref.watch(lastWornProvider);
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
        final theme = Theme.of(context);
        final rows = [
          for (final units in GarmentTwins.group(sorted))
            if (units.length == 1)
              _pickTile(l10n, units.single, rotation)
            else
              _twinsTile(l10n, units, lastWorn),
        ];
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
              child: Text(
                l10n.wearPickHint,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.wearSelected(_selected.length),
                      key: const Key('wear-selected'),
                      style: theme.textTheme.titleSmall,
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
            const SizedBox(height: 8),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (final (i, row) in rows.indexed) ...[
                    if (i > 0) const Divider(height: 1, indent: 72),
                    row,
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _pickTile(
    AppLocalizations l10n,
    Garment g,
    Map<GarmentId, RotationState>? rotation,
  ) => CheckboxListTile(
    key: Key('wear-pick-${g.id.value}'),
    value: _selected.contains(g.id),
    onChanged: (on) => setState(
      () => on == true ? _selected.add(g.id) : _selected.remove(g.id),
    ),
    title: _title(l10n, garmentLabel(l10n, g), [g.id]),
    subtitle: _subtitle(l10n, g, rotation?[g.id]),
    secondary: _thumb(g),
  );

  /// Peças iguais numa linha: escolher o grupo usa a unidade disponível
  /// há mais tempo sem uso; desmarcar tira qualquer uma delas.
  Widget _twinsTile(
    AppLocalizations l10n,
    List<Garment> units,
    Map<GarmentId, CalendarDay> lastWorn,
  ) {
    final chosen = units.any((g) => _selected.contains(g.id));
    return CheckboxListTile(
      key: Key('wear-pick-twins-${units.first.id.value}'),
      value: chosen,
      onChanged: (on) => setState(() {
        if (on == true) {
          _selected.add(GarmentTwins.pick(units, lastWorn: lastWorn).id);
        } else {
          _selected.removeAll([for (final g in units) g.id]);
        }
      }),
      title: _title(
        l10n,
        '${garmentLabel(l10n, units.first)} ×${units.length}',
        [for (final g in units) g.id],
      ),
      subtitle: Text(l10n.wearTwinsPick(units.length)),
      secondary: _thumb(units.first),
    );
  }

  /// Com a peça escolhida, um botão para a marcar para lavar já.
  Widget _title(AppLocalizations l10n, String label, List<GarmentId> ids) {
    final chosen = [
      for (final id in ids)
        if (_selected.contains(id)) id,
    ];
    if (chosen.isEmpty) return Text(label);
    final on = chosen.any(_dirtyNow.contains);
    return Row(
      children: [
        Expanded(child: Text(label)),
        IconButton(
          key: Key('wear-dirty-${ids.first.value}'),
          tooltip: l10n.wearDirtyNow,
          isSelected: on,
          icon: const Icon(Icons.water_drop_outlined),
          selectedIcon: const Icon(Icons.water_drop),
          onPressed: () => setState(
            () => on ? _dirtyNow.removeAll(chosen) : _dirtyNow.addAll(chosen),
          ),
        ),
      ],
    );
  }

  static Widget _thumb(Garment g) => ClipRRect(
    borderRadius: const BorderRadius.all(Radius.circular(10)),
    child: g.photos.isEmpty
        ? const SizedBox.square(
            dimension: 44,
            child: Icon(Icons.checkroom_outlined),
          )
        : GarmentPhotoView(photo: g.photos.first, size: 44),
  );

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
    // Lidos antes de esperar: o ecrã fecha logo a seguir.
    final wardrobe = ref.read(wardrobeRepositoryProvider);
    final garments = ref.read(allGarmentsProvider).value;
    final wears = ref.read(allWearsProvider).value;
    final cleanings = ref.read(allCleaningsProvider).value;
    final policies = ref.read(carePoliciesProvider).value;
    final WearResult<WearEvent> result = switch (widget.eventId) {
      final id? => await repo.correctWear(id, _selected),
      null => await repo.recordWear(
        todayFrom(ref.read(clockProvider)),
        _selected,
        planEntryId: widget.planEntryId,
      ),
    };
    if (!mounted) return;
    if (!reportWear(context, result)) {
      setState(() => _saving = false);
      return;
    }
    final event = (result as Ok<WearEvent, WearFailure>).value;
    // Lavandaria sozinha (2026-11-06): o que chega ao limiar vai para
    // lavar; só volta com "Lavei hoje" ou à mão.
    // E as que o utilizador marcou para lavar já (nódoa, uso intenso).
    final dirty = <Garment>[];
    if (wardrobe != null && garments != null) {
      final byId = {for (final g in garments) g.id: g};
      final toMark = {
        if (wears != null && cleanings != null && policies != null)
          ...LaundryPolicy.dirtyAfterWear(
            event,
            garments: garments,
            wears: wears,
            cleanings: cleanings,
            policies: policies,
          ),
        for (final id in _dirtyNow)
          if (_selected.contains(id) && (byId[id]?.isCandidate ?? false)) id,
      };
      for (final id in toMark) {
        final marked = await wardrobe.setAvailability(
          id,
          Availability.needsCleaning,
        );
        if (marked is Ok) dirty.add(byId[id]!);
      }
    }
    if (!mounted) return;
    setState(() => _saving = false);
    final done = _correcting ? l10n.wearCorrected : l10n.wearRecorded;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            dirty.isEmpty
                ? done
                : '$done ${l10n.wearMarkedDirty(dirty.length, [for (final g in dirty) garmentLabel(l10n, g)].join(', '))}',
            key: const Key('wear-saved-message'),
          ),
          action: _correcting
              ? null
              : SnackBarAction(
                  label: l10n.wearUndo,
                  onPressed: () async {
                    await repo.voidWear(event.id);
                    for (final g in dirty) {
                      await wardrobe?.setAvailability(g.id, g.availability);
                    }
                  },
                ),
        ),
      );
    context.pop();
  }
}
