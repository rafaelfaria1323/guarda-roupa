import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/domain/result.dart';
import '../../../l10n/app_localizations.dart';
import '../../engine/application/suggestion_providers.dart';
import '../../engine/presentation/today_suggestions_card.dart';
import '../../outfits/application/outfit_providers.dart';
import '../../outfits/domain/outfit.dart';
import '../../outfits/presentation/outfit_messages.dart';
import '../../photo_ai/presentation/photo_read_messages.dart';
import '../../wardrobe/domain/garment.dart';
import '../application/stylist_providers.dart';
import '../domain/stylist.dart';

/// "Pedir ao stylist" (docs/features/ia-gemini.md): por baixo da sugestão
/// do motor, só com o Gemini ligado. O Gemini escolhe um conjunto entre as
/// peças disponíveis e explica porquê; a app confirma antes de mostrar. Se
/// falhar, a sugestão do motor continua lá em cima.
class StylistSection extends ConsumerStatefulWidget {
  const StylistSection({super.key});

  @override
  ConsumerState<StylistSection> createState() => _StylistSectionState();
}

class _StylistSectionState extends ConsumerState<StylistSection> {
  final _ask = TextEditingController();
  var _loading = false;
  var _saving = false;
  StylistPick? _pick;
  String? _error;

  @override
  void dispose() {
    _ask.dispose();
    super.dispose();
  }

  List<GarmentId> get _current => [
    for (final i in _pick?.candidate.outfitItems ?? const <OutfitItem>[])
      i.garmentId,
  ];

  /// [ask]: mudança pedida à ideia atual; sem ela, uma ideia diferente.
  Future<void> _run({String? ask}) async {
    final stylist = ref.read(activeStylistProvider);
    final snapshot = ref.read(wardrobeSnapshotProvider);
    if (stylist == null || snapshot == null) return;
    final l10n = AppLocalizations.of(context);
    final request = ref.read(todayRequestProvider);
    final brief = StylistBrief.build(
      snapshot,
      request,
      ask: ask,
      previous: _current,
    );
    if (!brief.isEnough) {
      setState(() => _error = l10n.stylistTooFew);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await stylist.suggest(brief.json);
    if (!mounted) return;
    setState(() {
      _loading = false;
      switch (result) {
        case Ok(:final value):
          final pick = reviewStylistReply(value, brief, snapshot, request);
          if (pick == null) {
            _error = l10n.stylistIncomplete;
          } else {
            _pick = pick;
            _ask.clear();
          }
        case Err(:final failure):
          _error = photoReadMessage(l10n, failure);
      }
    });
  }

  Future<void> _save(StylistPick pick) async {
    final repo = ref.read(outfitRepositoryProvider);
    if (repo == null) return;
    final occasion = ref.read(suggestionChoicesProvider).occasion;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    final result = await repo.createOutfit(
      OutfitDraft(
        items: pick.candidate.outfitItems,
        occasions: {?occasion},
        name: pick.name,
      ),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (!reportOutfit(context, result)) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l10n.suggestionsOutfitSaved)));
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(activeStylistProvider) == null ||
        ref.watch(wardrobeSnapshotProvider) == null) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final pick = _pick;
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Column(
      key: const Key('stylist'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        if (pick == null)
          OutlinedButton.icon(
            key: const Key('stylist-ask'),
            onPressed: _loading ? null : _run,
            icon: _loading
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_awesome_outlined),
            label: Text(_loading ? l10n.stylistThinking : l10n.stylistAsk),
          )
        else ...[
          Text(l10n.stylistTitle, style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          SuggestionCandidateView(
            key: ValueKey(_current.join(',')),
            index: 0,
            total: 1,
            candidate: pick.candidate,
            heading: pick.name ?? l10n.stylistTitle,
            keyPrefix: 'stylist-pick',
          ),
          if (pick.why case final why?)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(why, key: const Key('stylist-why'), style: muted),
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton(
                key: const Key('stylist-wear'),
                onPressed: () => context.push(
                  AppRoutes.wearWith([
                    for (final i in pick.candidate.items) i.garment.id.value,
                  ]),
                ),
                child: Text(l10n.suggestionsWearThis),
              ),
              TextButton(
                key: const Key('stylist-another'),
                onPressed: _loading ? null : _run,
                child: Text(l10n.stylistAnother),
              ),
              TextButton.icon(
                key: const Key('stylist-save'),
                onPressed: _saving ? null : () => _save(pick),
                icon: const Icon(Icons.bookmark_add_outlined),
                label: Text(l10n.suggestionsSaveOutfit),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            key: const Key('stylist-change'),
            controller: _ask,
            enabled: !_loading,
            maxLength: 200,
            textInputAction: TextInputAction.send,
            decoration: InputDecoration(
              labelText: l10n.stylistChange,
              hintText: l10n.stylistChangeHint,
              counterText: '',
              suffixIcon: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : IconButton(
                      key: const Key('stylist-change-send'),
                      tooltip: l10n.stylistChangeSend,
                      icon: const Icon(Icons.send),
                      onPressed: () => _sendChange(),
                    ),
            ),
            onSubmitted: (_) => _sendChange(),
          ),
        ],
        if (_error case final error?)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              error,
              key: const Key('stylist-error'),
              style: muted?.copyWith(color: theme.colorScheme.error),
            ),
          ),
        if (pick == null && _error == null && !_loading)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              l10n.stylistHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }

  void _sendChange() {
    final text = _ask.text.trim();
    if (text.isEmpty || _loading) return;
    _run(ask: text);
  }
}
