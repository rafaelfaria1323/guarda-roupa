import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../l10n/app_localizations.dart';
import '../../engine/application/suggestion_providers.dart';
import '../../engine/domain/comfort.dart';
import '../../engine/domain/daily_engine.dart';
import '../../engine/domain/look_target.dart';
import '../../engine/domain/suggestion.dart';
import '../../engine/presentation/today_suggestions_card.dart';
import '../../local_ai/application/local_ai_providers.dart';
import '../../outfits/application/outfit_providers.dart';
import '../../outfits/domain/outfit.dart';
import '../../outfits/presentation/outfit_messages.dart';
import '../../account_sync/application/providers.dart';
import '../../wardrobe/domain/garment.dart';
import '../../wardrobe/domain/garment_photo.dart';
import '../../wear/application/wear_providers.dart';
import '../../stylist/presentation/stylist_section.dart';
import '../application/inspiration_providers.dart';
import '../domain/inspiration.dart';

/// "Montar com o que tenho": conjuntos do motor do dia, só com peças
/// próprias e disponíveis, ordenados pelo que têm da inspiração
/// ([LookTarget]). Tudo neste dispositivo; a inspiração não muda nada.
class InspirationLookScreen extends ConsumerStatefulWidget {
  const InspirationLookScreen({super.key, required this.id});

  final String id;

  @override
  ConsumerState<InspirationLookScreen> createState() =>
      _InspirationLookScreenState();
}

/// Estado da comparação da imagem com as peças.
enum _Image { none, comparing, done, failed }

class _InspirationLookScreenState extends ConsumerState<InspirationLookScreen> {
  Stream<Inspiration?>? _stream;
  var _seed = 0;
  var _saving = false;

  var _image = _Image.none;
  (int, int)? _progress;
  Set<GarmentId> _similar = const {};
  String? _comparedPhoto;

  Future<void> _compare(
    Inspiration inspiration,
    WardrobeSnapshot snapshot,
  ) async {
    final photo = inspiration.image;
    final finder = ref.read(similarGarmentsFinderProvider);
    final wardrobe = ref.read(wardrobeRepositoryProvider);
    if (photo == null || finder == null || wardrobe == null) return;
    _comparedPhoto = photo.id;
    setState(() {
      _image = _Image.comparing;
      _progress = (0, 0);
    });
    try {
      final query = await wardrobe.photoBytes(photo.id, PhotoVariant.thumb);
      final found = query == null
          ? null
          : await finder.find(
              query,
              snapshot.garments,
              top: LookTarget.similarOverall,
              onProgress: (done, total) {
                if (mounted) setState(() => _progress = (done, total));
              },
            );
      if (!mounted) return;
      setState(() {
        if (found == null) {
          _image = _Image.failed;
        } else {
          _image = _Image.done;
          _similar = LookTarget.similarFrom([
            for (final (g, _) in found.items) g,
          ]);
        }
      });
    } on Object {
      if (mounted) setState(() => _image = _Image.failed);
    } finally {
      if (mounted) setState(() => _progress = null);
    }
  }

  Future<void> _save(OutfitCandidate candidate, Inspiration inspiration) async {
    final repo = ref.read(outfitRepositoryProvider);
    if (repo == null) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    final result = await repo.createOutfit(
      OutfitDraft(
        name: inspiration.title,
        items: candidate.outfitItems,
        occasions: inspiration.occasions,
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
    final l10n = AppLocalizations.of(context);
    final repo = ref.watch(inspirationRepositoryProvider);
    if (repo != null) _stream ??= repo.watchInspiration(widget.id);
    final snapshot = ref.watch(wardrobeSnapshotProvider);
    final weather = ref.watch(todayConditionsProvider);
    final comfort =
        ref.watch(comfortThresholdsProvider).value ?? const ComfortThresholds();
    final today = todayFrom(ref.watch(clockProvider));
    final canCompare = ref.watch(similarGarmentsFinderProvider) != null;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.lookTitle)),
      body: StreamBuilder<Inspiration?>(
        stream: _stream,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting ||
              snapshot == null) {
            return const Center(child: CircularProgressIndicator());
          }
          final inspiration = snap.data;
          if (inspiration == null) {
            return Center(child: Text(l10n.inspirationNotFound));
          }
          final photo = inspiration.image;
          if (photo != null && canCompare && photo.id != _comparedPhoto) {
            _comparedPhoto = photo.id;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) unawaited(_compare(inspiration, snapshot));
            });
          }
          final result = DailyEngine.suggest(
            snapshot,
            SuggestionRequest(
              day: today,
              occasion: LookTarget.occasionOf(inspiration),
              weather: weather,
              comfort: comfort,
              seed: _seed,
              look: LookTarget.fromInspiration(inspiration, similar: _similar),
            ),
          );
          return _body(context, inspiration, result, canCompare: canCompare);
        },
      ),
    );
  }

  Widget _body(
    BuildContext context,
    Inspiration inspiration,
    SuggestionResult result, {
    required bool canCompare,
  }) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final look = LookTarget.fromInspiration(inspiration, similar: _similar);
    final occasion = LookTarget.occasionOf(inspiration);
    final searching = [
      if (look.palette.isNotEmpty) l10n.lookAspectLabel(LookAspect.color.name),
      if (look.formality != null)
        l10n.lookAspectLabel(LookAspect.formality.name),
      if (look.patterns.isNotEmpty)
        l10n.lookAspectLabel(LookAspect.pattern.name),
      if (look.textures.isNotEmpty)
        l10n.lookAspectLabel(LookAspect.texture.name),
      if (look.proportions.isNotEmpty)
        l10n.lookAspectLabel(LookAspect.proportion.name),
      if (look.similar.isNotEmpty) l10n.lookAspectLabel(LookAspect.image.name),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        if (inspiration.title case final title?)
          Text(title, style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          searching.isEmpty
              ? l10n.lookNothingToMatch
              : l10n.lookSearching(searching.join(', ')),
          key: const Key('look-searching'),
          style: muted,
        ),
        if (occasion != null)
          Text(
            l10n.noteOccasionMatches(l10n.occasionLabel(occasion.id)),
            style: muted,
          ),
        ..._imageStatus(context, inspiration, canCompare: canCompare),
        const SizedBox(height: 12),
        ..._result(context, result, inspiration),
        StylistSection(inspiration: inspiration),
        const SizedBox(height: 16),
        Text(l10n.lookFootnote, style: theme.textTheme.bodySmall),
      ],
    );
  }

  List<Widget> _imageStatus(
    BuildContext context,
    Inspiration inspiration, {
    required bool canCompare,
  }) {
    final l10n = AppLocalizations.of(context);
    final small = Theme.of(context).textTheme.bodySmall;
    if (inspiration.image == null) return const [];
    if (!canCompare) {
      return [Text(l10n.lookImageNoModel, style: small)];
    }
    return switch (_image) {
      _Image.comparing => [
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: switch (_progress) {
            (final done, final total) when total > 0 => done / total,
            _ => null,
          },
        ),
        const SizedBox(height: 4),
        Text(
          l10n.similarGarmentsProgress(_progress?.$1 ?? 0, _progress?.$2 ?? 0),
          style: small,
        ),
      ],
      _Image.failed => [Text(l10n.similarGarmentsFailed, style: small)],
      _Image.none || _Image.done => const [],
    };
  }

  List<Widget> _result(
    BuildContext context,
    SuggestionResult result,
    Inspiration inspiration,
  ) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final gaps = [
      for (final g in result.gaps)
        Text(
          l10n.suggestionsGap(l10n.outfitRoleLabel(g.role.id), g.cause.name),
          style: muted,
        ),
    ];
    switch (result.status) {
      case SuggestionStatus.insufficientData:
        return [Text(l10n.suggestionsInsufficient, style: muted)];
      case SuggestionStatus.notFound:
        return [Text(l10n.suggestionsNotFound, style: muted), ...gaps];
      case SuggestionStatus.valid || SuggestionStatus.partial:
    }
    final candidates = result.candidates;
    return [
      for (final (i, c) in candidates.indexed) ...[
        SuggestionCandidateView(
          key: Key('look-$i-${_key(c)}'),
          index: i,
          total: candidates.length,
          candidate: c,
        ),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            FilledButton(
              key: Key('look-$i-wear'),
              onPressed: () => context.push(
                AppRoutes.wearWith([
                  for (final it in c.items) it.garment.id.value,
                ]),
              ),
              child: Text(l10n.suggestionsWearThis),
            ),
            if (!c.notes.any((n) => n is SavedOutfitNote && n.swaps.isEmpty))
              TextButton.icon(
                key: Key('look-$i-save'),
                onPressed: _saving ? null : () => _save(c, inspiration),
                icon: const Icon(Icons.bookmark_add_outlined),
                label: Text(l10n.suggestionsSaveOutfit),
              ),
          ],
        ),
        const Divider(height: 32),
      ],
      ...gaps,
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          key: const Key('look-more'),
          onPressed: () => setState(() => _seed++),
          icon: const Icon(Icons.refresh),
          label: Text(l10n.lookMore),
        ),
      ),
    ];
  }

  static String _key(OutfitCandidate c) =>
      ([for (final i in c.items) i.garment.id.value]..sort()).join(',');
}
