import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../app/theme.dart';
import '../../../core/domain/result.dart';
import '../../../l10n/app_localizations.dart';
import '../../engine/application/suggestion_providers.dart';
import '../../engine/presentation/today_suggestions_card.dart';
import '../../inspirations/application/inspiration_providers.dart';
import '../../inspirations/domain/inspiration.dart';
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
/// falhar, a sugestão do motor continua lá em cima. Leva as inspirações
/// guardadas; com [inspiration] (em "Montar com o que tenho") pede um look
/// parecido com essa.
class StylistSection extends ConsumerStatefulWidget {
  const StylistSection({super.key, this.inspiration});

  final Inspiration? inspiration;

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
      inspirations: ref.read(inspirationsProvider).value ?? const [],
      target: widget.inspiration,
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
    final look = widget.inspiration != null;
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    final colors = AppColors.of(context);
    final busy = const SizedBox.square(
      dimension: 16,
      child: CircularProgressIndicator(strokeWidth: 2),
    );

    return Padding(
      key: const Key('stylist'),
      padding: const EdgeInsets.only(top: 16),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.accentSoft,
                      shape: BoxShape.circle,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Icon(
                        Icons.auto_awesome,
                        size: 18,
                        color: colors.onAccentSoft,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      l10n.stylistTitle,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
              if (pick == null) ...[
                if (_error == null && !_loading) ...[
                  const SizedBox(height: 8),
                  Text(
                    look ? l10n.stylistLookHint : l10n.stylistHint,
                    style: muted,
                  ),
                ],
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonalIcon(
                    key: const Key('stylist-ask'),
                    onPressed: _loading ? null : _run,
                    icon: _loading
                        ? busy
                        : const Icon(Icons.auto_awesome_outlined),
                    label: Text(
                      _loading
                          ? l10n.stylistThinking
                          : look
                          ? l10n.stylistAskLook
                          : l10n.stylistAsk,
                    ),
                  ),
                ),
              ] else ...[
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
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colors.surfaceMuted,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.format_quote_rounded,
                          size: 18,
                          color: colors.accent,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            why,
                            key: const Key('stylist-why'),
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        key: const Key('stylist-wear'),
                        onPressed: () => context.push(
                          AppRoutes.wearWith([
                            for (final i in pick.candidate.items)
                              i.garment.id.value,
                          ]),
                        ),
                        icon: const Icon(Icons.done_all),
                        label: Text(l10n.suggestionsWearThis),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      key: const Key('stylist-save'),
                      tooltip: l10n.suggestionsSaveOutfit,
                      onPressed: _saving ? null : () => _save(pick),
                      icon: const Icon(Icons.bookmark_add_outlined),
                    ),
                    IconButton.filledTonal(
                      key: const Key('stylist-another'),
                      tooltip: l10n.stylistAnother,
                      onPressed: _loading ? null : _run,
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
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
                        ? Padding(
                            padding: const EdgeInsets.all(12),
                            child: busy,
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
            ],
          ),
        ),
      ),
    );
  }

  void _sendChange() {
    final text = _ask.text.trim();
    if (text.isEmpty || _loading) return;
    _run(ask: text);
  }
}
