import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../core/domain/result.dart';
import '../../../l10n/app_localizations.dart';
import '../../care/application/care_providers.dart';
import '../../wardrobe/domain/garment.dart';
import '../../wardrobe/domain/garment_attributes.dart';
import '../../wardrobe/domain/garment_category.dart';
import '../../wardrobe/presentation/garment_cutout.dart';
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
  CategoryGroup? _group;

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
    final groups = [
      for (final group in CategoryGroup.values)
        if (candidates.any((g) => g.category.group == group)) group,
    ];
    final group = groups.contains(_group) ? _group : null;
    final shown = [
      for (final g in candidates)
        if (group == null || g.category.group == group) g,
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        TextField(
          key: const Key('outfit-name'),
          controller: _name,
          maxLength: OutfitRules.maxName,
          decoration: InputDecoration(labelText: l10n.outfitName),
        ),
        Text(l10n.outfitOccasions, style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
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
        const SizedBox(height: 20),
        _Canvas(
          items: _items,
          byId: byId,
          onRole: (index, role) => setState(
            () => _items[index] = OutfitItem(_items[index].garmentId, role),
          ),
          onRemove: (index) => setState(() => _items.removeAt(index)),
        ),
        const SizedBox(height: 16),
        _Panel(
          key: const Key('outfit-tray'),
          children: [
            Text(l10n.outfitChoose, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              candidates.isEmpty ? l10n.outfitChooseEmpty : l10n.outfitTapToAdd,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.of(context).onSurfaceMuted,
              ),
            ),
            if (groups.length > 1) ...[
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final g in [null, ...groups])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          key: Key('outfit-group-${g?.name ?? 'all'}'),
                          label: Text(
                            g == null
                                ? l10n.outfitsAllOccasions
                                : l10n.categoryGroupLabel(g.name),
                          ),
                          selected: g == group,
                          onSelected: (_) => setState(() => _group = g),
                        ),
                      ),
                  ],
                ),
              ),
            ],
            if (shown.isNotEmpty) ...[
              const SizedBox(height: 12),
              _Grid(
                columns: 3,
                children: [
                  for (final g in shown)
                    _CandidateCard(
                      key: Key('outfit-add-${g.id.value}'),
                      garment: g,
                      onTap: () => setState(
                        () => _items.add(
                          OutfitItem(
                            g.id,
                            OutfitRole.suggestFor(
                              g.category,
                              _items.map((i) => i.role),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ],
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

class _Panel extends StatelessWidget {
  const _Panel({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    ),
  );
}

/// Grelha simples, sem ser preguiçosa: todas as peças existem na árvore.
class _Grid extends StatelessWidget {
  const _Grid({required this.columns, required this.children});

  final int columns;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      const gap = 12.0;
      final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final child in children) SizedBox(width: width, child: child),
        ],
      );
    },
  );
}

/// A composição: as peças escolhidas, com o papel de cada uma.
class _Canvas extends StatelessWidget {
  const _Canvas({
    required this.items,
    required this.byId,
    required this.onRole,
    required this.onRemove,
  });

  final List<OutfitItem> items;
  final Map<GarmentId, Garment> byId;
  final void Function(int index, OutfitRole role) onRole;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final unavailable = items
        .where((i) => pieceWarning(l10n, byId[i.garmentId]) != null)
        .length;
    return _Panel(
      key: const Key('outfit-canvas'),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.outfitCanvas.toUpperCase(),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colors.onSurfaceMuted,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            if (items.isNotEmpty)
              Flexible(
                flex: 2,
                child: _StatusPill(
                  key: const Key('outfit-availability'),
                  icon: unavailable == 0
                      ? Icons.check_circle_outline
                      : Icons.error_outline,
                  label: unavailable == 0
                      ? l10n.outfitAllAvailable
                      : l10n.outfitUnavailable(unavailable),
                  warn: unavailable > 0,
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (items.isEmpty)
          Container(
            height: 120,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.surfaceMuted,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              Icons.checkroom_outlined,
              color: colors.faint,
              size: 40,
            ),
          )
        else
          _Grid(
            columns: 2,
            children: [
              for (final (index, item) in items.indexed)
                _PieceCard(
                  key: Key('outfit-item-${item.garmentId.value}'),
                  item: item,
                  garment: byId[item.garmentId],
                  takenByOthers: {
                    for (final (i, other) in items.indexed)
                      if (i != index && other.role.single) other.role,
                  },
                  onRole: (role) => onRole(index, role),
                  onRemove: () => onRemove(index),
                ),
            ],
          ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                items.isEmpty ? l10n.outfitNoPieces : outfitShape(l10n, items),
                key: const Key('outfit-shape'),
                style: theme.textTheme.bodyMedium,
              ),
            ),
            if (items.isNotEmpty) ...[
              const SizedBox(width: 12),
              Text(
                l10n.outfitPiecesCount(items.length),
                key: const Key('outfit-count'),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colors.onSurfaceMuted,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.icon,
    required this.label,
    required this.warn,
    super.key,
  });

  final IconData icon;
  final String label;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final fg = warn ? colors.onCareSoft : colors.onAccentSoft;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: warn ? colors.care.withValues(alpha: 0.14) : colors.accentSoft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(color: fg),
            ),
          ),
        ],
      ),
    );
  }
}

class _Square extends StatelessWidget {
  const _Square({required this.garment, this.overlay = const []});

  final Garment? garment;
  final List<Widget> overlay;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return AspectRatio(
      aspectRatio: 1,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceMuted,
          borderRadius: BorderRadius.circular(16),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) => Stack(
            children: [
              Center(
                child: switch (garment) {
                  final g? => GarmentCutout(
                    garment: g,
                    size: constraints.maxWidth * 0.72,
                  ),
                  null => Icon(Icons.help_outline, color: colors.faint),
                },
              ),
              ...overlay,
            ],
          ),
        ),
      ),
    );
  }
}

class _PieceCard extends StatelessWidget {
  const _PieceCard({
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
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final warning = pieceWarning(l10n, garment);
    final id = item.garmentId.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Square(
          garment: garment,
          overlay: [
            Positioned(
              top: 4,
              right: 4,
              child: IconButton.filledTonal(
                key: Key('outfit-remove-$id'),
                tooltip: l10n.outfitRemove,
                visualDensity: VisualDensity.compact,
                iconSize: 18,
                onPressed: onRemove,
                icon: const Icon(Icons.close),
              ),
            ),
            if (warning != null)
              Positioned(
                left: 8,
                bottom: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: colors.care.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    warning,
                    key: Key('outfit-warning-$id'),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          garmentLabel(l10n, garment),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleSmall,
        ),
        DropdownButtonHideUnderline(
          child: DropdownButton<OutfitRole>(
            key: Key('outfit-role-$id'),
            value: item.role,
            isDense: true,
            isExpanded: true,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceMuted,
            ),
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
        ),
      ],
    );
  }
}

class _CandidateCard extends StatelessWidget {
  const _CandidateCard({required this.garment, required this.onTap, super.key});

  final Garment garment;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final warning = pieceWarning(l10n, garment);
    return Semantics(
      button: true,
      label: '${l10n.outfitAddPiece}: ${garmentLabel(l10n, garment)}',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Square(
              garment: garment,
              overlay: [
                Positioned(
                  top: 6,
                  right: 6,
                  child: CircleAvatar(
                    radius: 12,
                    backgroundColor: colors.accent,
                    child: Icon(Icons.add, size: 16, color: colors.onAccent),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              garmentLabel(l10n, garment),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge,
            ),
            Text(
              warning ?? l10n.categoryLabel(garment.category.id),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: warning != null ? colors.care : colors.onSurfaceMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
