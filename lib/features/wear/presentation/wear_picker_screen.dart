import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/domain/result.dart';
import '../../../l10n/app_localizations.dart';
import '../../account_sync/application/providers.dart';
import '../../wardrobe/domain/garment.dart';
import '../../wardrobe/domain/garment_filter.dart';
import '../../wardrobe/presentation/garment_photo_view.dart';
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
              child: Text(
                l10n.wearSelected(_selected.length),
                key: const Key('wear-selected'),
                style: Theme.of(context).textTheme.labelLarge,
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
                subtitle: g.name == null
                    ? null
                    : Text(l10n.categoryLabel(g.category.id)),
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
