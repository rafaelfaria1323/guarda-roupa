import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/domain/result.dart';
import '../../../l10n/app_localizations.dart';
import '../../account_sync/application/providers.dart';
import '../../local_ai/application/local_ai_providers.dart';
import '../application/batch_add.dart';
import '../application/photo_providers.dart';
import '../data/photo_processor.dart';
import '../domain/garment.dart';
import '../domain/garment_category.dart';
import 'garment_cutout.dart';

/// "Várias fotos de uma vez": escolhe-se até [batchMaxPhotos] fotos da
/// galeria e cada uma passa a uma peça, com a categoria e as cores
/// sugeridas pela foto. Depois só se confirma a categoria de cada uma com
/// um toque (ou se abre a peça para o resto).
class BatchAddScreen extends ConsumerStatefulWidget {
  const BatchAddScreen({super.key});

  @override
  ConsumerState<BatchAddScreen> createState() => _BatchAddScreenState();
}

class _BatchAddScreenState extends ConsumerState<BatchAddScreen> {
  /// Uma entrada por foto escolhida; `null` = ainda a preparar.
  final _rows = <BatchOutcome?>[];
  bool _picking = false;
  bool _working = false;

  /// Peças com a categoria mudada aqui (já não é só uma sugestão).
  final _chosen = <GarmentId>{};

  Future<void> _pick() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _picking = true);
    final List<Uint8List> photos;
    try {
      // Pedido logo no toque: o Safari só abre a galeria assim.
      photos = await ref
          .read(photoPickerProvider)
          .pickMany(limit: batchMaxPhotos);
    } on Object {
      messenger.showSnackBar(SnackBar(content: Text(l10n.photoPickFailed)));
      return;
    } finally {
      if (mounted) setState(() => _picking = false);
    }
    if (photos.isEmpty || !mounted) return;
    await _create(photos.take(batchMaxPhotos).toList());
  }

  Future<void> _create(List<Uint8List> photos) async {
    final repo = ref.read(wardrobeRepositoryProvider);
    if (repo == null) return;
    final process = ref.read(photoProcessorProvider);
    final suggester = ref.read(categorySuggesterProvider);
    final remover = ref.read(backgroundRemoverProvider);
    final start = _rows.length;
    setState(() {
      _working = true;
      _rows.addAll(List.filled(photos.length, null));
    });
    try {
      for (final (i, bytes) in photos.indexed) {
        final outcome = await addPhotoAsGarment(
          bytes,
          repo: repo,
          process: process,
          suggester: suggester,
          remover: remover,
        );
        if (!mounted) return;
        setState(() => _rows[start + i] = outcome);
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _setCategory(int index, GarmentCategory category) async {
    final row = _rows[index];
    final repo = ref.read(wardrobeRepositoryProvider);
    if (row is! BatchCreated || repo == null) return;
    if (row.garment.category == category) {
      setState(() => _chosen.add(row.garment.id));
      return;
    }
    final result = await repo.updateGarment(
      row.garment.id,
      withCategory(row.garment, category),
    );
    if (!mounted) return;
    if (result case Ok(value: final garment)) {
      setState(() {
        _rows[index] = BatchCreated(garment, row.suggestions);
        _chosen.add(garment.id);
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).batchSaveFailed)),
      );
    }
  }

  Future<void> _otherCategory(int index) async {
    final l10n = AppLocalizations.of(context);
    final picked = await showModalBottomSheet<GarmentCategory>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ListView(
          key: const Key('batch-categories'),
          shrinkWrap: true,
          children: [
            for (final c in GarmentCategory.values)
              ListTile(
                key: Key('batch-category-${c.id}'),
                title: Text(l10n.categoryLabel(c.id)),
                onTap: () => Navigator.pop(context, c),
              ),
          ],
        ),
      ),
    );
    if (picked != null && mounted) await _setCategory(index, picked);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final created = _rows.whereType<BatchCreated>().length;
    final failed = _rows.whereType<BatchFailed>().length;
    final pending = _rows.where((r) => r == null).length;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.batchTitle)),
      bottomNavigationBar: _rows.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: FilledButton(
                  key: const Key('batch-done'),
                  onPressed: _working
                      ? null
                      : () => context.canPop()
                            ? context.pop()
                            : context.go(AppRoutes.wardrobe),
                  child: Text(l10n.batchDone),
                ),
              ),
            ),
      body: _rows.isEmpty
          ? ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Icon(
                  Icons.photo_library_outlined,
                  size: 48,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(l10n.batchIntro, style: theme.textTheme.bodyLarge),
                const SizedBox(height: 8),
                Text(
                  ref.watch(categorySuggesterProvider) == null
                      ? l10n.batchNoModel
                      : l10n.batchHint,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  key: const Key('batch-pick'),
                  onPressed: _picking ? null : _pick,
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: Text(l10n.batchPick(batchMaxPhotos)),
                ),
              ],
            )
          : ListView(
              key: const Key('batch-list'),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                Text(
                  pending > 0
                      ? l10n.batchProgress(created + failed, _rows.length)
                      : l10n.batchCreated(created),
                  key: const Key('batch-summary'),
                  style: theme.textTheme.titleMedium,
                ),
                if (pending == 0 && created > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      l10n.batchReviewHint,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                if (pending > 0)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: LinearProgressIndicator(),
                  ),
                const SizedBox(height: 8),
                for (final (i, row) in _rows.indexed)
                  switch (row) {
                    null => ListTile(
                      key: Key('batch-row-$i'),
                      leading: const SizedBox.square(
                        dimension: 56,
                        child: Center(child: CircularProgressIndicator()),
                      ),
                      title: Text(l10n.batchPreparing),
                    ),
                    BatchFailed(:final problem) => ListTile(
                      key: Key('batch-row-$i'),
                      leading: Icon(
                        Icons.error_outline,
                        color: theme.colorScheme.error,
                      ),
                      title: Text(switch (problem) {
                        PhotoProblem.heic => l10n.photoHeic,
                        PhotoProblem.unsupportedFormat => l10n.photoUnsupported,
                        PhotoProblem.tooLarge => l10n.photoTooLarge,
                        null => l10n.batchSaveFailed,
                      }),
                    ),
                    BatchCreated() => _CreatedRow(
                      key: Key('batch-row-$i'),
                      row: row,
                      chosen: _chosen.contains(row.garment.id),
                      onCategory: (c) => _setCategory(i, c),
                      onOther: () => _otherCategory(i),
                    ),
                  },
                if (!_working && created + failed == _rows.length)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: OutlinedButton.icon(
                      key: const Key('batch-more'),
                      onPressed: _picking ? null : _pick,
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                      label: Text(l10n.batchMore),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _CreatedRow extends StatelessWidget {
  const _CreatedRow({
    required this.row,
    required this.chosen,
    required this.onCategory,
    required this.onOther,
    super.key,
  });

  final BatchCreated row;
  final bool chosen;
  final void Function(GarmentCategory) onCategory;
  final VoidCallback onOther;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final g = row.garment;
    final options = [
      ...row.suggestions.take(3),
      if (!row.suggestions.take(3).contains(g.category)) g.category,
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            key: Key('batch-open-${g.id.value}'),
            borderRadius: BorderRadius.circular(12),
            onTap: () => unawaited(context.push(AppRoutes.garment(g.id))),
            child: GarmentCutout(garment: g, size: 72),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  chosen || row.suggestions.isEmpty
                      ? l10n.garmentCategory
                      : l10n.batchSuggested,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final c in options)
                      ChoiceChip(
                        key: Key('batch-chip-${g.id.value}-${c.id}'),
                        label: Text(l10n.categoryLabel(c.id)),
                        selected: g.category == c,
                        onSelected: (_) => onCategory(c),
                      ),
                    ActionChip(
                      key: Key('batch-other-${g.id.value}'),
                      label: Text(l10n.batchOtherCategory),
                      onPressed: onOther,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
