import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/domain/result.dart';
import '../../../l10n/app_localizations.dart';
import '../../wardrobe/domain/garment_attributes.dart';
import '../../wardrobe/presentation/colors_editor.dart';
import '../application/inspiration_providers.dart';
import '../domain/inspiration_repository.dart';
import '../domain/style_preference.dart';
import 'preference_messages.dart';

/// Criar (`id == null`) ou editar uma preferência de estilo. Ao editar, o
/// assunto (cor, padrão…) fica fixo; muda-se o valor, a posição e o
/// contexto.
class PreferenceEditorScreen extends ConsumerStatefulWidget {
  const PreferenceEditorScreen({this.id, super.key});

  final String? id;

  @override
  ConsumerState<PreferenceEditorScreen> createState() =>
      _PreferenceEditorScreenState();
}

class _PreferenceEditorScreenState
    extends ConsumerState<PreferenceEditorScreen> {
  PreferenceStance _stance = PreferenceStance.like;
  PreferenceSubject _subject = PreferenceSubject.color;
  String? _value;
  final _occasions = <Occasion>{};
  String? _inspirationId;
  bool _loaded = false;
  bool _saving = false;
  Stream<StylePreference?>? _current;

  bool get _editing => widget.id != null;

  void _load(StylePreference p) {
    _stance = p.stance;
    _subject = p.subject;
    _value = p.value;
    _occasions.addAll(p.occasions);
    _inspirationId = p.inspirationId;
    _loaded = true;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final repo = ref.watch(preferenceRepositoryProvider);
    if (repo == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (widget.id case final id?) _current ??= repo.watchPreference(id);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _editing ? l10n.preferenceEditTitle : l10n.preferenceNewTitle,
        ),
        actions: [
          if (_editing)
            IconButton(
              key: const Key('preference-delete'),
              tooltip: l10n.preferenceDelete,
              onPressed: _saving || !_loaded ? null : () => _delete(repo),
              icon: const Icon(Icons.delete_outline),
            ),
          TextButton(
            key: const Key('preference-save'),
            onPressed: _saving || _value == null || (_editing && !_loaded)
                ? null
                : () => _save(repo),
            child: Text(l10n.inspirationSave),
          ),
        ],
      ),
      body: StreamBuilder<StylePreference?>(
        stream: _current,
        builder: (context, snapshot) {
          if (_editing && !_loaded) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final current = snapshot.data;
            if (current == null) {
              return Center(child: Text(l10n.preferenceNotFound));
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

    final values = [
      ...preferenceValues(_subject),
      if (_value case final v? when !preferenceValues(_subject).contains(v)) v,
    ];

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Text(l10n.preferenceHint, style: theme.textTheme.bodySmall),
        ),
        heading(l10n.preferenceStance),
        chips([
          for (final s in PreferenceStance.values)
            ChoiceChip(
              key: Key('preference-stance-${s.id}'),
              label: Text(l10n.preferenceStanceLabel(s.id)),
              selected: _stance == s,
              onSelected: (_) => setState(() => _stance = s),
            ),
        ]),
        heading(l10n.preferenceSubject),
        chips([
          for (final s in PreferenceSubject.values)
            ChoiceChip(
              key: Key('preference-subject-${s.id}'),
              label: Text(l10n.preferenceSubjectLabel(s.id)),
              selected: _subject == s,
              onSelected: _editing
                  ? null
                  : (_) => setState(() {
                      if (_subject != s) _value = null;
                      _subject = s;
                    }),
            ),
        ]),
        heading(l10n.preferenceValue),
        chips([
          for (final v in values)
            if (_subject == PreferenceSubject.color)
              ColorDot(
                key: Key('preference-value-$v'),
                rgb: int.parse(v),
                label: preferenceValueLabel(l10n, _subject, v),
                selected: _value == v,
                onTap: () => setState(() => _value = v),
              )
            else
              ChoiceChip(
                key: Key('preference-value-$v'),
                label: Text(preferenceValueLabel(l10n, _subject, v)),
                selected: _value == v,
                onSelected: (_) => setState(() => _value = v),
              ),
        ]),
        heading(l10n.preferenceOccasions),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            l10n.preferenceOccasionsHint,
            style: theme.textTheme.bodySmall,
          ),
        ),
        chips([
          for (final o in Occasion.values)
            FilterChip(
              key: Key('preference-occasion-${o.id}'),
              label: Text(l10n.occasionLabel(o.id)),
              selected: _occasions.contains(o),
              onSelected: (on) =>
                  setState(() => on ? _occasions.add(o) : _occasions.remove(o)),
            ),
        ]),
      ],
    );
  }

  Future<void> _save(StylePreferenceRepository repo) async {
    final value = _value;
    if (value == null) return;
    setState(() => _saving = true);
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final draft = PreferenceDraft(
      subject: _subject,
      value: value,
      stance: _stance,
      occasions: {..._occasions},
      inspirationId: _inspirationId,
    );
    final result = switch (widget.id) {
      final id? => await repo.updatePreference(id, draft),
      null => await repo.createPreference(draft),
    };
    if (!mounted) return;
    setState(() => _saving = false);
    if (!reportPreference(context, result)) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l10n.preferenceSaved)));
    context.pop();
  }

  Future<void> _delete(StylePreferenceRepository repo) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(l10n.preferenceDeleteConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            key: const Key('preference-delete-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.preferenceDelete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final result = await repo.deletePreference(widget.id!);
    if (!mounted || !reportPreference(context, result)) return;
    if (result case Ok()) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.preferenceDeleted)));
      context.pop();
    }
  }
}
