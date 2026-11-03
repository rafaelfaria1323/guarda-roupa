import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/domain/result.dart';
import '../../../l10n/app_localizations.dart';
import '../../wardrobe/domain/garment_attributes.dart';
import '../../wardrobe/domain/reference_color.dart';
import '../../wardrobe/presentation/colors_editor.dart';
import '../application/inspiration_providers.dart';
import '../domain/inspiration.dart';
import '../domain/inspiration_repository.dart';
import 'inspiration_messages.dart';

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
  bool _loaded = false;
  bool _saving = false;
  Stream<Inspiration?>? _current;

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
          return _form(context);
        },
      ),
    );
  }

  Widget _form(BuildContext context) {
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
        ListTile(
          title: Text(l10n.inspirationTags, style: theme.textTheme.titleMedium),
          subtitle: Text(l10n.inspirationTagsHint),
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
      ],
    );
  }

  Widget _toggle<T>(String key, String label, Set<T> set, T value) =>
      FilterChip(
        key: Key(key),
        label: Text(label),
        selected: set.contains(value),
        onSelected: (on) =>
            setState(() => on ? set.add(value) : set.remove(value)),
      );

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
    final result = switch (widget.id) {
      final id? => await repo.updateInspiration(id, _draft),
      null => await repo.createInspiration(_draft),
    };
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
