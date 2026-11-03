import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/domain/result.dart';
import '../../../l10n/app_localizations.dart';
import '../../care/application/care_providers.dart';
import '../../wardrobe/domain/garment.dart';
import '../../wardrobe/domain/garment_attributes.dart';
import '../../wardrobe/presentation/garment_photo_view.dart';
import '../../wear/presentation/today_wear_card.dart';
import '../application/outfit_providers.dart';
import '../domain/outfit.dart';
import '../domain/outfit_repository.dart';
import 'outfit_messages.dart';

/// Criar (`id == null`) ou editar um conjunto guardado. Editar não muda
/// utilizações já registadas.
class OutfitEditorScreen extends ConsumerStatefulWidget {
  const OutfitEditorScreen({this.id, super.key});

  final String? id;

  @override
  ConsumerState<OutfitEditorScreen> createState() => _OutfitEditorScreenState();
}

class _OutfitEditorScreenState extends ConsumerState<OutfitEditorScreen> {
  final _name = TextEditingController();
  final _occasions = <Occasion>{};
  final _items = <OutfitItem>[];
  bool _loaded = false;
  bool _saving = false;
  Stream<Outfit?>? _outfit;

  bool get _editing => widget.id != null;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final repo = ref.watch(outfitRepositoryProvider);
    if (repo == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (widget.id case final id?) _outfit ??= repo.watchOutfit(id);

    return Scaffold(
      appBar: AppBar(
        title: Text(_editing ? l10n.outfitEditTitle : l10n.outfitNewTitle),
        actions: [
          if (_editing)
            IconButton(
              key: const Key('outfit-delete'),
              tooltip: l10n.outfitDelete,
              onPressed: _saving || !_loaded ? null : () => _delete(repo),
              icon: const Icon(Icons.delete_outline),
            ),
          TextButton(
            key: const Key('outfit-save'),
            onPressed: _saving || (_editing && !_loaded)
                ? null
                : () => _save(repo),
            child: Text(l10n.outfitSave),
          ),
        ],
      ),
      body: StreamBuilder<Outfit?>(
        stream: _outfit,
        builder: (context, snapshot) {
          if (_editing && !_loaded) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final current = snapshot.data;
            if (current == null) {
              return Center(child: Text(l10n.outfitNotFound));
            }
            _name.text = current.name ?? '';
            _occasions.addAll(current.occasions);
            _items.addAll(current.items);
            _loaded = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() {});
            });
          }
          return _form(context);
        },
      ),
    );
  }

  Widget _form(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final all = ref.watch(allGarmentsProvider).value;
    if (all == null) return const Center(child: CircularProgressIndicator());
    final byId = {for (final g in all) g.id: g};
    final chosen = {for (final i in _items) i.garmentId};
    final candidates =
        [
          for (final g in all)
            if (!g.isArchived && !chosen.contains(g.id)) g,
        ]..sort((a, b) {
          final byCategory = a.category.index.compareTo(b.category.index);
          if (byCategory != 0) return byCategory;
          return (a.name ?? '').compareTo(b.name ?? '');
        });

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: TextField(
            key: const Key('outfit-name'),
            controller: _name,
            maxLength: OutfitRules.maxName,
            decoration: InputDecoration(labelText: l10n.outfitName),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(l10n.outfitOccasions, style: theme.textTheme.titleSmall),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Wrap(
            spacing: 8,
            children: [
              for (final o in Occasion.values)
                FilterChip(
                  key: Key('outfit-occasion-${o.id}'),
                  label: Text(l10n.occasionLabel(o.id)),
                  selected: _occasions.contains(o),
                  onSelected: (on) => setState(
                    () => on ? _occasions.add(o) : _occasions.remove(o),
                  ),
                ),
            ],
          ),
        ),
        const Divider(),
        ListTile(
          title: Text(l10n.outfitPieces, style: theme.textTheme.titleMedium),
          subtitle: Text(
            _items.isEmpty ? l10n.outfitNoPieces : outfitShape(l10n, _items),
            key: const Key('outfit-shape'),
          ),
        ),
        for (final (index, item) in _items.indexed)
          _ItemTile(
            key: Key('outfit-item-${item.garmentId.value}'),
            item: item,
            garment: byId[item.garmentId],
            takenByOthers: {
              for (final (i, other) in _items.indexed)
                if (i != index && other.role.single) other.role,
            },
            onRole: (role) => setState(
              () => _items[index] = OutfitItem(item.garmentId, role),
            ),
            onRemove: () => setState(() => _items.removeAt(index)),
          ),
        const Divider(),
        ListTile(
          title: Text(l10n.outfitChoose, style: theme.textTheme.titleMedium),
          subtitle: candidates.isEmpty ? Text(l10n.outfitChooseEmpty) : null,
        ),
        for (final g in candidates)
          ListTile(
            key: Key('outfit-add-${g.id.value}'),
            leading: _thumb(g),
            title: Text(garmentLabel(l10n, g)),
            subtitle: switch ([
              if (g.name != null) l10n.categoryLabel(g.category.id),
              ?pieceWarning(l10n, g),
            ]) {
              final List<String> lines when lines.isNotEmpty => Text(
                lines.join(' · '),
              ),
              _ => null,
            },
            trailing: Icon(Icons.add, semanticLabel: l10n.outfitAddPiece),
            onTap: () => setState(
              () => _items.add(
                OutfitItem(
                  g.id,
                  OutfitRole.suggestFor(g.category, _items.map((i) => i.role)),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _save(OutfitRepository repo) async {
    setState(() => _saving = true);
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final draft = OutfitDraft(
      name: _name.text,
      occasions: {..._occasions},
      items: [..._items],
    );
    final result = switch (widget.id) {
      final id? => await repo.updateOutfit(id, draft),
      null => await repo.createOutfit(draft),
    };
    if (!mounted) return;
    setState(() => _saving = false);
    if (!reportOutfit(context, result)) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l10n.outfitSaved)));
    context.pop();
  }

  Future<void> _delete(OutfitRepository repo) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(l10n.outfitDeleteConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            key: const Key('outfit-delete-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.outfitDelete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final result = await repo.deleteOutfit(widget.id!);
    if (!mounted || !reportOutfit(context, result)) return;
    if (result case Ok()) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.outfitDeleted)));
      context.pop();
    }
  }
}

Widget _thumb(Garment? g) => g == null || g.photos.isEmpty
    ? const SizedBox.square(
        dimension: 40,
        child: Icon(Icons.checkroom_outlined),
      )
    : GarmentPhotoView(photo: g.photos.first, size: 40);

class _ItemTile extends StatelessWidget {
  const _ItemTile({
    required this.item,
    required this.garment,
    required this.takenByOthers,
    required this.onRole,
    required this.onRemove,
    super.key,
  });

  final OutfitItem item;
  final Garment? garment;
  final Set<OutfitRole> takenByOthers;
  final ValueChanged<OutfitRole> onRole;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final warning = pieceWarning(l10n, garment);
    final id = item.garmentId.value;
    return ListTile(
      leading: _thumb(garment),
      title: Text(garmentLabel(l10n, garment)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (warning != null)
            Text(
              warning,
              key: Key('outfit-warning-$id'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          DropdownButton<OutfitRole>(
            key: Key('outfit-role-$id'),
            value: item.role,
            isDense: true,
            isExpanded: true,
            onChanged: (role) {
              if (role != null) onRole(role);
            },
            items: [
              for (final role in OutfitRole.values)
                DropdownMenuItem(
                  key: Key('outfit-role-$id-${role.id}'),
                  value: role,
                  enabled: !takenByOthers.contains(role),
                  child: Text(
                    l10n.outfitRoleLabel(role.id),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
        ],
      ),
      trailing: IconButton(
        key: Key('outfit-remove-$id'),
        tooltip: l10n.outfitRemove,
        onPressed: onRemove,
        icon: const Icon(Icons.close),
      ),
    );
  }
}
