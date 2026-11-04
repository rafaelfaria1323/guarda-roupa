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
import '../domain/garment_attributes.dart';
import '../domain/garment_category.dart';
import '../domain/garment_photo.dart';
import '../domain/photo_colors.dart';
import '../domain/photo_picker.dart';
import '../domain/wardrobe_repository.dart';
import '../domain/garment_color.dart';
import '../../care/presentation/garment_laundry_section.dart';
import '../../import/application/import_providers.dart';
import '../../local_ai/application/local_ai_providers.dart';
import '../../local_ai/domain/category_suggester.dart';
import '../domain/foreground_mask.dart';
import '../../import/domain/product_import.dart';
import '../../import/presentation/import_link_screen.dart';
import '../../care/presentation/garment_rotation_section.dart';
import '../../wear/presentation/garment_wear_summary.dart';
import 'attributes_editor.dart';
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
  final _material = TextEditingController();
  final _care = TextEditingController();
  GarmentCategory? _category;

  /// Categorias sugeridas pela foto, à espera de um toque; `null` = nenhuma.
  List<GarmentCategory>? _categorySuggestions;

  /// Muda quando a categoria muda por código: o campo só lê o valor inicial.
  int _categoryRevision = 0;
  List<GarmentColor> _colors = const [];
  GarmentAttributes _attributes = const GarmentAttributes();
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
    _material.dispose();
    _care.dispose();
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
    _attributes = garment.attributes;
    _material.text = garment.attributes.material ?? '';
    _care.text = garment.attributes.care ?? '';
  }

  GarmentDraft _draft() => GarmentDraft(
    category: _category!,
    name: _name.text,
    brand: _brand.text,
    notes: _notes.text,
    colors: _colors,
    attributes: _attributes.copyWith(
      material: () => _material.text,
      care: () => _care.text,
    ),
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

  /// Preenche a peça nova com o que o utilizador escolheu num link. A
  /// categoria e as cores ficam por escolher aqui.
  Future<void> _import(ProductImporter importer) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final imported = await Navigator.of(context).push<ImportedGarment>(
      MaterialPageRoute(
        builder: (_) => ImportLinkScreen(
          importer: importer,
          maxImages: PhotoRules.maxPerGarment - _pending.length,
        ),
      ),
    );
    if (imported == null || !mounted) return;
    setState(() {
      if (imported.name case final v?) _name.text = v;
      if (imported.brand case final v?) _brand.text = v;
      if (imported.notes case final v?) _notes.text = v;
      if (imported.material case final v?) _material.text = v;
      _processing = imported.images.isNotEmpty;
    });
    var failed = imported.failedImages;
    final process = ref.read(photoProcessorProvider);
    try {
      for (final bytes in imported.images) {
        if (_pending.length >= PhotoRules.maxPerGarment) break;
        switch (await process(bytes)) {
          case Ok(value: final photo):
            if (mounted) setState(() => _pending.add(photo));
          case Err():
            failed++;
        }
      }
    } finally {
      if (mounted) setState(() => _processing = false);
    }
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          failed > 0 ? l10n.importImagesFailed(failed) : l10n.importDone,
        ),
      ),
    );
  }

  /// Miniatura da capa (a primeira foto).
  Future<Uint8List?> _coverThumb(WardrobeRepository repo, Garment? garment) =>
      garment == null
      ? Future.value(_pending.first.thumb)
      : repo.photoBytes(garment.photos.first.id, PhotoVariant.thumb);

  /// Categorias prováveis da capa, para escolher com um toque. Nunca muda a
  /// categoria sozinha.
  Future<void> _suggestCategory(
    WardrobeRepository repo,
    Garment? garment,
    CategorySuggester suggester,
  ) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _processing = true);
    List<GarmentCategory>? found;
    try {
      final bytes = await _coverThumb(repo, garment);
      found = bytes == null ? null : await suggester.suggest(bytes);
    } on Object {
      found = null;
    } finally {
      if (mounted) setState(() => _processing = false);
    }
    if (!mounted) return;
    if (found == null || found.isEmpty) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.categorySuggestFailed)),
      );
      return;
    }
    setState(() => _categorySuggestions = found);
  }

  /// Cores da primeira foto (a capa), por confirmar. Substitui as atuais,
  /// com "Desfazer". Com o modelo de recorte neste dispositivo, o fundo
  /// tira-se primeiro; se o recorte falhar, segue sem ele.
  Future<void> _suggestColors(WardrobeRepository repo, Garment? garment) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final remover = ref.read(backgroundRemoverProvider);
    setState(() => _processing = true);
    List<GarmentColor> colors;
    ForegroundMask? mask;
    try {
      final bytes = await _coverThumb(repo, garment);
      if (bytes != null && remover != null) {
        try {
          mask = await remover.mask(bytes);
        } on Object {
          mask = null;
        }
      }
      // A miniatura (≤ 320 px) analisa-se em milissegundos: sem isolate.
      colors = bytes == null
          ? const []
          : PhotoColors.suggest(bytes, mask: mask);
    } on Object {
      colors = const [];
    } finally {
      if (mounted) setState(() => _processing = false);
    }
    if (!mounted) return;
    messenger.hideCurrentSnackBar();
    if (colors.isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.colorsSuggestFailed)));
      return;
    }
    final before = _colors;
    setState(() => _colors = colors);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          mask == null ? l10n.colorsSuggested : l10n.colorsSuggestedCutout,
        ),
        action: SnackBarAction(
          label: l10n.wearUndo,
          onPressed: () {
            if (mounted) setState(() => _colors = before);
          },
        ),
      ),
    );
  }

  /// Botão "Sugerir categoria pela foto" (com o modelo neste dispositivo e
  /// uma foto) ou as sugestões, cada uma escolhível com um toque.
  List<Widget> _categoryFromPhoto(WardrobeRepository repo, Garment? garment) {
    final suggester = ref.watch(categorySuggesterProvider);
    final hasPhoto = garment?.photos.isNotEmpty ?? _pending.isNotEmpty;
    if (suggester == null || !hasPhoto) return const [];
    final l10n = AppLocalizations.of(context);
    final suggestions = _categorySuggestions;
    if (suggestions == null) {
      return [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            key: const Key('category-from-photo'),
            onPressed: _processing || _saving
                ? null
                : () => _suggestCategory(repo, garment, suggester),
            icon: const Icon(Icons.auto_awesome_outlined),
            label: Text(l10n.categoryFromPhoto),
          ),
        ),
      ];
    }
    return [
      const SizedBox(height: 8),
      Text(l10n.categorySuggestions),
      const SizedBox(height: 4),
      Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final c in suggestions)
            ActionChip(
              key: Key('category-suggestion-${c.id}'),
              label: Text(l10n.categoryLabel(c.id)),
              onPressed: () => setState(() {
                _category = c;
                _categoryRevision++;
                _categorySuggestions = null;
              }),
            ),
        ],
      ),
    ];
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
            if (garment == null)
              if (ref.watch(productImporterProvider) case final importer?)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      key: const Key('garment-import'),
                      onPressed: _saving || _processing
                          ? null
                          : () => _import(importer),
                      icon: const Icon(Icons.link),
                      label: Text(l10n.importFromLink),
                    ),
                  ),
                ),
            _photoSection(repo, garment),
            KeyedSubtree(
              key: ValueKey(_categoryRevision),
              child: DropdownButtonFormField<GarmentCategory>(
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
                onChanged: (value) => setState(() {
                  _category = value;
                  _categorySuggestions = null;
                }),
              ),
            ),
            ..._categoryFromPhoto(repo, garment),
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
              onSuggest:
                  _processing || (garment?.photos.isEmpty ?? _pending.isEmpty)
                  ? null
                  : () => _suggestColors(repo, garment),
            ),
            const SizedBox(height: 16),
            AttributesEditor(
              value: _attributes,
              onChanged: (value) => setState(() => _attributes = value),
              material: _material,
              care: _care,
              maxLength: _maxLength,
            ),
            if (garment != null) ...[
              const SizedBox(height: 24),
              GarmentWearSummary(garmentId: garment.id),
              const SizedBox(height: 24),
              GarmentLaundrySection(garment: garment),
              const SizedBox(height: 24),
              GarmentRotationSection(garment: garment),
            ],
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
