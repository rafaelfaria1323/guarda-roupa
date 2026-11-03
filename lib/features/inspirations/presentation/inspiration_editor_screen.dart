import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/domain/result.dart';
import '../../../l10n/app_localizations.dart';
import '../../wardrobe/application/photo_providers.dart';
import '../../wardrobe/data/photo_processor.dart';
import '../../wardrobe/domain/garment_attributes.dart';
import '../../wardrobe/domain/garment_photo.dart';
import '../../wardrobe/domain/photo_picker.dart';
import '../../wardrobe/domain/reference_color.dart';
import '../../wardrobe/presentation/colors_editor.dart';
import '../../wardrobe/presentation/garment_photo_view.dart';
import '../application/inspiration_providers.dart';
import '../domain/inspiration.dart';
import '../domain/inspiration_repository.dart';
import '../domain/style_preference.dart';
import 'inspiration_messages.dart';
import 'preference_messages.dart';

/// Criar (`id == null`) ou editar uma inspiração. As etiquetas são só as
/// que o utilizador escolhe; nada é deduzido do link.
class InspirationEditorScreen extends ConsumerStatefulWidget {
  const InspirationEditorScreen({this.id, super.key});

  final String? id;

  @override
  ConsumerState<InspirationEditorScreen> createState() =>
      _InspirationEditorScreenState();
}

class _InspirationEditorScreenState
    extends ConsumerState<InspirationEditorScreen> {
  final _title = TextEditingController();
  final _link = TextEditingController();
  final _notes = TextEditingController();
  final _palette = <int>[];
  Formality? _formality;
  final _patterns = <GarmentPattern>{};
  final _textures = <SurfaceTexture>{};
  final _occasions = <Occasion>{};
  final _proportions = <Proportion>{};

  /// Imagem escolhida antes de a inspiração existir; liga-se ao guardar.
  ProcessedPhoto? _pendingImage;
  bool _rightsConfirmed = false;
  bool _processing = false;
  bool _loaded = false;
  bool _saving = false;
  Stream<Inspiration?>? _current;

  /// A versão guardada (as preferências nascem dela, não do rascunho).
  Inspiration? _saved;

  bool get _editing => widget.id != null;

  @override
  void dispose() {
    _title.dispose();
    _link.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _load(Inspiration i) {
    _title.text = i.title ?? '';
    _link.text = i.sourceUrl ?? '';
    _notes.text = i.notes ?? '';
    _palette.addAll(i.palette);
    _formality = i.formality;
    _patterns.addAll(i.patterns);
    _textures.addAll(i.textures);
    _occasions.addAll(i.occasions);
    _proportions.addAll(i.proportions);
    _loaded = true;
  }

  InspirationDraft get _draft => InspirationDraft(
    title: _title.text,
    sourceUrl: _link.text,
    notes: _notes.text,
    palette: [..._palette],
    formality: _formality,
    patterns: {..._patterns},
    textures: {..._textures},
    occasions: {..._occasions},
    proportions: {..._proportions},
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final repo = ref.watch(inspirationRepositoryProvider);
    if (repo == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (widget.id case final id?) _current ??= repo.watchInspiration(id);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _editing ? l10n.inspirationEditTitle : l10n.inspirationNewTitle,
        ),
        actions: [
          if (_editing)
            IconButton(
              key: const Key('inspiration-delete'),
              tooltip: l10n.inspirationDelete,
              onPressed: _saving || !_loaded ? null : () => _delete(repo),
              icon: const Icon(Icons.delete_outline),
            ),
          TextButton(
            key: const Key('inspiration-save'),
            onPressed: _saving || (_editing && !_loaded)
                ? null
                : () => _save(repo),
            child: Text(l10n.inspirationSave),
          ),
        ],
      ),
      body: StreamBuilder<Inspiration?>(
        stream: _current,
        builder: (context, snapshot) {
          _saved = snapshot.data;
          if (_editing && !_loaded) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final current = snapshot.data;
            if (current == null) {
              return Center(child: Text(l10n.inspirationNotFound));
            }
            _load(current);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() {});
            });
          }
          return _form(context, repo);
        },
      ),
    );
  }

  Widget _form(BuildContext context, InspirationRepository repo) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(text, style: theme.textTheme.titleSmall),
    );
    Widget chips(List<Widget> children) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Wrap(spacing: 8, runSpacing: 4, children: children),
    );

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Text(
            l10n.inspirationNotOwned,
            style: theme.textTheme.bodySmall,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: TextField(
            key: const Key('inspiration-title'),
            controller: _title,
            maxLength: InspirationRules.maxTitle,
            decoration: InputDecoration(labelText: l10n.inspirationTitle),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            key: const Key('inspiration-link'),
            controller: _link,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: l10n.inspirationLink,
              helperText: l10n.inspirationLinkHint,
              helperMaxLines: 2,
              suffixIcon: _link.text.trim().isEmpty
                  ? null
                  : IconButton(
                      key: const Key('inspiration-copy-link'),
                      tooltip: l10n.inspirationCopyLink,
                      icon: const Icon(Icons.copy),
                      onPressed: _copyLink,
                    ),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: TextField(
            key: const Key('inspiration-notes'),
            controller: _notes,
            maxLength: InspirationRules.maxNotes,
            minLines: 1,
            maxLines: 4,
            decoration: InputDecoration(labelText: l10n.inspirationNotes),
          ),
        ),
        const Divider(),
        _imageSection(repo),
        const Divider(),
        ListTile(
          title: Text(l10n.inspirationTags, style: theme.textTheme.titleMedium),
          subtitle: Text(l10n.inspirationTagsHint),
        ),
        if (_saved case final saved?
            when PreferenceDraft.fromInspiration(saved).isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: OutlinedButton.icon(
                key: const Key('inspiration-make-preferences'),
                onPressed: _saving ? null : () => _makePreferences(saved),
                icon: const Icon(Icons.thumbs_up_down_outlined),
                label: Text(l10n.inspirationMakePreferences),
              ),
            ),
          ),
        heading(l10n.inspirationPalette),
        chips([
          for (final color in ReferenceColor.values)
            ColorDot(
              key: Key('inspiration-color-${color.id}'),
              rgb: color.rgb,
              label: l10n.colorLabel(color.id),
              selected: _palette.contains(color.rgb),
              onTap: () => setState(() {
                if (!_palette.remove(color.rgb) &&
                    _palette.length < InspirationRules.maxColors) {
                  _palette.add(color.rgb);
                }
              }),
            ),
        ]),
        heading(l10n.inspirationFormality),
        chips([
          for (final f in [null, ...Formality.values])
            ChoiceChip(
              key: Key('inspiration-formality-${f?.id ?? 'none'}'),
              label: Text(l10n.formalityLabel(f?.id ?? 'none')),
              selected: _formality == f,
              onSelected: (_) => setState(() => _formality = f),
            ),
        ]),
        heading(l10n.inspirationOccasions),
        chips([
          for (final o in Occasion.values)
            _toggle(
              'inspiration-occasion-${o.id}',
              l10n.occasionLabel(o.id),
              _occasions,
              o,
            ),
        ]),
        heading(l10n.inspirationPatterns),
        chips([
          for (final p in GarmentPattern.values)
            _toggle(
              'inspiration-pattern-${p.id}',
              l10n.patternLabel(p.id),
              _patterns,
              p,
            ),
        ]),
        heading(l10n.inspirationTextures),
        chips([
          for (final t in SurfaceTexture.values)
            _toggle(
              'inspiration-texture-${t.id}',
              l10n.textureLabel(t.id),
              _textures,
              t,
            ),
        ]),
        heading(l10n.inspirationProportions),
        chips([
          for (final p in Proportion.values)
            _toggle(
              'inspiration-proportion-${p.id}',
              l10n.proportionLabel(p.id),
              _proportions,
              p,
            ),
        ]),
      ],
    );
  }

  Widget _imageSection(InspirationRepository repo) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final saved = _editing ? _saved : null;
    final Widget? preview = switch ((saved?.image, _pendingImage)) {
      (final GarmentPhoto image, _) => GarmentPhotoView(
        photo: image,
        size: 160,
      ),
      (null, final ProcessedPhoto pending) => ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.memory(
          pending.thumb,
          width: 160,
          height: 160,
          fit: BoxFit.cover,
        ),
      ),
      _ => null,
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.inspirationImage, style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(l10n.inspirationImageHint, style: theme.textTheme.bodySmall),
          const SizedBox(height: 8),
          if (preview != null)
            Stack(
              children: [
                Semantics(
                  key: const Key('inspiration-image'),
                  label: l10n.inspirationImage,
                  child: preview,
                ),
                Positioned(
                  top: 0,
                  right: 0,
                  child: IconButton.filledTonal(
                    key: const Key('inspiration-image-remove'),
                    visualDensity: VisualDensity.compact,
                    iconSize: 18,
                    tooltip: l10n.photoRemove,
                    onPressed: _saving || _processing
                        ? null
                        : () => _removeImage(repo),
                    icon: const Icon(Icons.close),
                  ),
                ),
              ],
            ),
          if (preview != null) const SizedBox(height: 8),
          if (_processing)
            const Padding(
              padding: EdgeInsets.all(8),
              child: SizedBox.square(
                dimension: 24,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  key: const Key('inspiration-image-camera'),
                  onPressed: _saving
                      ? null
                      : () => _pickImage(repo, PhotoSource.camera),
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: Text(l10n.photoTake),
                ),
                OutlinedButton.icon(
                  key: const Key('inspiration-image-gallery'),
                  onPressed: _saving
                      ? null
                      : () => _pickImage(repo, PhotoSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: Text(
                    preview == null
                        ? l10n.photoPick
                        : l10n.inspirationImageReplace,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  /// A imagem tem de ser do utilizador ou autorizada; pergunta-se uma vez
  /// por ecrã, antes de abrir a câmara ou a galeria.
  Future<bool> _confirmRights() async {
    if (_rightsConfirmed) return true;
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.inspirationImageRightsTitle),
        content: Text(l10n.inspirationImageRightsBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            key: const Key('inspiration-image-rights-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.inspirationImageRightsConfirm),
          ),
        ],
      ),
    );
    _rightsConfirmed = ok ?? false;
    return _rightsConfirmed;
  }

  Future<void> _pickImage(
    InspirationRepository repo,
    PhotoSource source,
  ) async {
    if (!await _confirmRights() || !mounted) return;
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
        case Ok(value: final image):
          if (widget.id case final id?) {
            final result = await repo.setImage(id, image);
            if (mounted) reportInspiration(context, result);
          } else if (mounted) {
            setState(() => _pendingImage = image);
          }
      }
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _removeImage(InspirationRepository repo) async {
    if (widget.id case final id?) {
      final result = await repo.removeImage(id);
      if (mounted) reportInspiration(context, result);
    } else {
      setState(() => _pendingImage = null);
    }
  }

  Widget _toggle<T>(String key, String label, Set<T> set, T value) =>
      FilterChip(
        key: Key(key),
        label: Text(label),
        selected: set.contains(value),
        onSelected: (on) =>
            setState(() => on ? set.add(value) : set.remove(value)),
      );

  /// Escolher que etiquetas guardadas passam a "gosto" (nada é criado sem
  /// confirmação; as repetidas são ignoradas).
  Future<void> _makePreferences(Inspiration saved) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final repo = ref.read(preferenceRepositoryProvider);
    if (repo == null) return;
    final drafts = PreferenceDraft.fromInspiration(saved);
    final chosen = await showDialog<List<PreferenceDraft>>(
      context: context,
      builder: (context) => _MakePreferencesDialog(drafts: drafts),
    );
    if (chosen == null || chosen.isEmpty || !mounted) return;
    final result = await repo.createPreferences(chosen);
    if (!mounted || !reportPreference(context, result)) return;
    if (result case Ok(:final value)) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(l10n.inspirationPreferencesCreated(value))),
        );
    }
  }

  Future<void> _copyLink() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final url = InspirationRules.normalizeUrl(_link.text);
    if (url == null) return;
    await Clipboard.setData(ClipboardData(text: url));
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l10n.inspirationLinkCopied)));
  }

  Future<void> _save(InspirationRepository repo) async {
    setState(() => _saving = true);
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    var result = switch (widget.id) {
      final id? => await repo.updateInspiration(id, _draft),
      null => await repo.createInspiration(_draft),
    };
    if (_pendingImage case final image? when widget.id == null) {
      if (result case Ok(value: final created)) {
        result = await repo.setImage(created.id, image);
      }
    }
    if (!mounted) return;
    setState(() => _saving = false);
    if (!reportInspiration(context, result)) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l10n.inspirationSaved)));
    context.pop();
  }

  Future<void> _delete(InspirationRepository repo) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(l10n.inspirationDeleteConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            key: const Key('inspiration-delete-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.inspirationDelete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final result = await repo.deleteInspiration(widget.id!);
    if (!mounted || !reportInspiration(context, result)) return;
    if (result case Ok()) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.inspirationDeleted)));
      context.pop();
    }
  }
}

class _MakePreferencesDialog extends StatefulWidget {
  const _MakePreferencesDialog({required this.drafts});

  final List<PreferenceDraft> drafts;

  @override
  State<_MakePreferencesDialog> createState() => _MakePreferencesDialogState();
}

class _MakePreferencesDialogState extends State<_MakePreferencesDialog> {
  late final _chosen = List.filled(widget.drafts.length, true);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final drafts = widget.drafts;
    final context0 = drafts.first.occasions.isEmpty
        ? l10n.preferenceAlways
        : [
            for (final o in Occasion.values)
              if (drafts.first.occasions.contains(o)) l10n.occasionLabel(o.id),
          ].join(', ');
    return AlertDialog(
      title: Text(l10n.inspirationMakePreferences),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            Text(l10n.inspirationMakePreferencesHint(context0)),
            for (final (i, d) in drafts.indexed)
              CheckboxListTile(
                key: Key('make-preference-$i'),
                contentPadding: EdgeInsets.zero,
                value: _chosen[i],
                onChanged: (on) => setState(() => _chosen[i] = on ?? false),
                title: Text(
                  l10n.preferenceTitle(
                    d.stance.id,
                    preferenceValueLabel(l10n, d.subject, d.value),
                  ),
                ),
                subtitle: Text(l10n.preferenceSubjectLabel(d.subject.id)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const Key('make-preferences-confirm'),
          onPressed: _chosen.contains(true)
              ? () => Navigator.pop(context, [
                  for (final (i, d) in drafts.indexed)
                    if (_chosen[i]) d,
                ])
              : null,
          child: Text(l10n.inspirationMakePreferencesConfirm),
        ),
      ],
    );
  }
}
