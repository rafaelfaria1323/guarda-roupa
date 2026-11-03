import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/domain/result.dart';
import '../../../l10n/app_localizations.dart';
import '../../account_sync/application/providers.dart';
import '../application/photo_providers.dart';
import '../data/photo_processor.dart';
import '../domain/availability.dart';
import '../domain/garment.dart';
import '../domain/garment_category.dart';
import '../domain/garment_photo.dart';
import '../domain/photo_picker.dart';
import '../domain/wardrobe_repository.dart';
import '../domain/garment_color.dart';
import 'colors_editor.dart';
import 'garment_photo_view.dart';
import 'labels.dart';

/// Criar (`id == null`) ou editar uma peça.
class GarmentFormScreen extends ConsumerStatefulWidget {
  const GarmentFormScreen({this.id, super.key});

  final GarmentId? id;

  @override
  ConsumerState<GarmentFormScreen> createState() => _GarmentFormScreenState();
}

class _GarmentFormScreenState extends ConsumerState<GarmentFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _brand = TextEditingController();
  final _notes = TextEditingController();
  GarmentCategory? _category;
  List<GarmentColor> _colors = const [];
  bool _loaded = false;
  bool _saving = false;
  bool _processing = false;

  /// Fotos de uma peça nova, ligadas depois de a guardar.
  final _pending = <ProcessedPhoto>[];

  WardrobeRepository? _repo;
  Stream<Garment?>? _garment;

  bool get _isNew => widget.id == null;

  @override
  void dispose() {
    _name.dispose();
    _brand.dispose();
    _notes.dispose();
    super.dispose();
  }

  Stream<Garment?>? _streamFor(WardrobeRepository? repo) {
    final id = widget.id;
    if (id == null) return null;
    if (repo != _repo) {
      _repo = repo;
      _garment = repo?.watchGarment(id);
    }
    return _garment;
  }

  /// Preenche o formulário uma única vez, para não apagar o que o utilizador
  /// está a escrever quando chega uma atualização sincronizada.
  void _fill(Garment garment) {
    if (_loaded) return;
    _loaded = true;
    _category = garment.category;
    _name.text = garment.name ?? '';
    _brand.text = garment.brand ?? '';
    _notes.text = garment.notes ?? '';
    _colors = garment.colors;
  }

  GarmentDraft _draft() => GarmentDraft(
    category: _category!,
    name: _name.text,
    brand: _brand.text,
    notes: _notes.text,
    colors: _colors,
  );

  Future<void> _save(WardrobeRepository repo, Garment? current) async {
    if (!_formKey.currentState!.validate()) return;
    if (ColorsEditor.totalPercent(_colors) > 100) return; // erro já visível
    setState(() => _saving = true);
    var result = current == null
        ? await repo.addGarment(_draft())
        : await repo.updateGarment(current.id, _draft());
    if (result case Ok(value: final created) when current == null) {
      for (final photo in _pending) {
        result = await repo.addPhoto(created.id, photo);
        if (result is Err) break;
      }
    }
    if (!mounted) return;
    setState(() => _saving = false);
    // Sem snackbar: a lista e o ícone de sincronização já mostram o resultado
    // (e um snackbar no shell tapava o botão de adicionar).
    _report(result, null, onOk: (_) => context.pop());
  }

  Future<void> _run(
    Future<WardrobeResult<Garment>> Function() action, {
    String? done,
    void Function(Garment)? onOk,
  }) async {
    final result = await action();
    if (mounted) _report(result, done, onOk: onOk);
  }

  void _report(
    WardrobeResult<Garment> result,
    String? done, {
    void Function(Garment)? onOk,
  }) {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    switch (result) {
      case Ok(value: final garment):
        if (done != null) {
          messenger.showSnackBar(SnackBar(content: Text(done)));
        }
        onOk?.call(garment);
      case Err(failure: final failure):
        final message = switch (failure) {
          GarmentNotFound() || GarmentDeleted() => l10n.garmentNotFound,
          InvalidDraft() || StorageFailure() => l10n.garmentSaveFailed,
          TooManyPhotos() => l10n.photoLimit(PhotoRules.maxPerGarment),
        };
        messenger.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _addPhoto(
    WardrobeRepository repo,
    Garment? garment,
    PhotoSource source,
  ) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final process = ref.read(photoProcessorProvider);
    setState(() => _processing = true);
    try {
      final Uint8List? input;
      try {
        input = await ref.read(photoPickerProvider).pick(source);
      } on Object {
        messenger.showSnackBar(SnackBar(content: Text(l10n.photoPickFailed)));
        return;
      }
      // Cancelar não é erro: não acontece nada.
      if (input == null || !mounted) return;
      switch (await process(input)) {
        case Err(failure: final problem):
          messenger.showSnackBar(
            SnackBar(
              content: Text(switch (problem) {
                PhotoProblem.heic => l10n.photoHeic,
                PhotoProblem.unsupportedFormat => l10n.photoUnsupported,
                PhotoProblem.tooLarge => l10n.photoTooLarge,
              }),
            ),
          );
        case Ok(value: final photo):
          if (garment == null) {
            if (mounted) setState(() => _pending.add(photo));
          } else {
            await _run(() => repo.addPhoto(garment.id, photo));
          }
      }
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _confirmDelete(WardrobeRepository repo, Garment garment) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.garmentDeleteConfirmTitle),
        content: Text(l10n.garmentDeleteConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            key: const Key('garment-delete-confirm'),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.garmentDelete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run(
      () => repo.deleteGarment(garment.id),
      onOk: (_) => context.pop(),
    );
  }

  Widget _photoSection(WardrobeRepository repo, Garment? garment) {
    final l10n = AppLocalizations.of(context);
    final count = garment?.photos.length ?? _pending.length;
    Widget removable(int index, Widget image, VoidCallback onRemove) => Stack(
      children: [
        Semantics(label: l10n.photoOf(index + 1), child: image),
        Positioned(
          top: 0,
          right: 0,
          child: IconButton.filledTonal(
            key: Key('photo-remove-$index'),
            visualDensity: VisualDensity.compact,
            iconSize: 18,
            tooltip: l10n.photoRemove,
            onPressed: onRemove,
            icon: const Icon(Icons.close),
          ),
        ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.garmentPhotos, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (garment != null)
              for (final (i, photo) in garment.photos.indexed)
                removable(
                  i,
                  GarmentPhotoView(photo: photo, size: 96),
                  () => _run(() => repo.removePhoto(garment.id, photo.id)),
                )
            else
              for (final (i, photo) in _pending.indexed)
                removable(
                  i,
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(
                      photo.thumb,
                      width: 96,
                      height: 96,
                      fit: BoxFit.cover,
                    ),
                  ),
                  () => setState(() => _pending.removeAt(i)),
                ),
          ],
        ),
        if (count > 0) const SizedBox(height: 8),
        if (_processing)
          const Padding(
            padding: EdgeInsets.all(8),
            child: SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
          )
        else if (count >= PhotoRules.maxPerGarment)
          Text(l10n.photoLimit(PhotoRules.maxPerGarment))
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                key: const Key('photo-camera'),
                onPressed: () => _addPhoto(repo, garment, PhotoSource.camera),
                icon: const Icon(Icons.photo_camera_outlined),
                label: Text(l10n.photoTake),
              ),
              OutlinedButton.icon(
                key: const Key('photo-gallery'),
                onPressed: () => _addPhoto(repo, garment, PhotoSource.gallery),
                icon: const Icon(Icons.photo_library_outlined),
                label: Text(l10n.photoPick),
              ),
            ],
          ),
        const SizedBox(height: 24),
      ],
    );
  }

  String? Function(String?) _maxLength(int max) =>
      (value) => (value?.trim().length ?? 0) > max
      ? AppLocalizations.of(context).garmentTooLong(max)
      : null;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final repo = ref.watch(wardrobeRepositoryProvider);
    final stream = _streamFor(repo);

    if (repo == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (stream == null) return _buildForm(context, repo, null);

    return StreamBuilder<Garment?>(
      stream: stream,
      builder: (context, snapshot) {
        if (!snapshot.hasData &&
            !snapshot.hasError &&
            snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final garment = snapshot.data;
        if (garment == null) {
          return Scaffold(
            appBar: AppBar(),
            body: Center(child: Text(l10n.garmentNotFound)),
          );
        }
        _fill(garment);
        return _buildForm(context, repo, garment);
      },
    );
  }

  Widget _buildForm(
    BuildContext context,
    WardrobeRepository repo,
    Garment? garment,
  ) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? l10n.garmentNew : l10n.garmentEdit),
        actions: [
          // Sempre visível: o formulário é comprido (fotos, cores).
          TextButton(
            key: const Key('garment-save'),
            onPressed: _saving || _processing
                ? null
                : () => _save(repo, garment),
            child: Text(l10n.garmentSave),
          ),
          if (garment != null)
            PopupMenuButton<void Function()>(
              onSelected: (action) => action(),
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: () => _run(
                    () => repo.duplicateGarment(garment.id),
                    done: l10n.garmentDuplicated,
                    onOk: (copy) =>
                        context.pushReplacement(AppRoutes.garment(copy.id)),
                  ),
                  child: Text(l10n.garmentDuplicate),
                ),
                PopupMenuItem(
                  value: garment.isArchived
                      ? () => _run(() => repo.unarchiveGarment(garment.id))
                      : () => _run(
                          () => repo.archiveGarment(garment.id),
                          onOk: (_) => context.pop(),
                        ),
                  child: Text(
                    garment.isArchived
                        ? l10n.garmentUnarchive
                        : l10n.garmentArchive,
                  ),
                ),
                PopupMenuItem(
                  value: () => _confirmDelete(repo, garment),
                  child: Text(l10n.garmentDelete),
                ),
              ],
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (garment?.isArchived ?? false)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Chip(
                  avatar: const Icon(Icons.inventory_2_outlined),
                  label: Text(l10n.garmentArchived),
                ),
              ),
            if (garment != null) ...[
              Text(
                l10n.garmentAvailability,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              // Aplicada de imediato: é uma transição explícita, não um campo
              // do formulário.
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final value in Availability.values)
                    ChoiceChip(
                      avatar: Icon(availabilityIcon(value)),
                      label: Text(l10n.availabilityLabel(value.id)),
                      selected: garment.availability == value,
                      onSelected: (_) =>
                          _run(() => repo.setAvailability(garment.id, value)),
                    ),
                ],
              ),
              const SizedBox(height: 24),
            ],
            _photoSection(repo, garment),
            DropdownButtonFormField<GarmentCategory>(
              key: const Key('garment-category'),
              initialValue: _category,
              decoration: InputDecoration(
                labelText: l10n.garmentCategory,
                border: const OutlineInputBorder(),
              ),
              items: [
                for (final category in GarmentCategory.values)
                  DropdownMenuItem(
                    value: category,
                    child: Text(l10n.categoryLabel(category.id)),
                  ),
              ],
              validator: (value) =>
                  value == null ? l10n.garmentCategoryRequired : null,
              onChanged: (value) => setState(() => _category = value),
            ),
            const SizedBox(height: 16),
            TextFormField(
              key: const Key('garment-name'),
              controller: _name,
              decoration: InputDecoration(
                labelText: l10n.garmentName,
                border: const OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.sentences,
              validator: _maxLength(GarmentRules.maxNameLength),
            ),
            const SizedBox(height: 16),
            TextFormField(
              key: const Key('garment-brand'),
              controller: _brand,
              decoration: InputDecoration(
                labelText: l10n.garmentBrand,
                border: const OutlineInputBorder(),
              ),
              validator: _maxLength(GarmentRules.maxBrandLength),
            ),
            const SizedBox(height: 16),
            TextFormField(
              key: const Key('garment-notes'),
              controller: _notes,
              decoration: InputDecoration(
                labelText: l10n.garmentNotes,
                border: const OutlineInputBorder(),
              ),
              minLines: 2,
              maxLines: 5,
              validator: _maxLength(GarmentRules.maxNotesLength),
            ),
            const SizedBox(height: 24),
            ColorsEditor(
              value: _colors,
              onChanged: (colors) => setState(() => _colors = colors),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
