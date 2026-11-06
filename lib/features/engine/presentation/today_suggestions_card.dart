import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../app/theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../outfits/application/outfit_providers.dart';
import '../../outfits/domain/outfit.dart';
import '../../outfits/presentation/outfit_messages.dart';
import '../../wardrobe/domain/garment_attributes.dart';
import '../../wardrobe/presentation/garment_cutout.dart';
import '../../wear/presentation/today_wear_card.dart';
import '../../weather/domain/weather.dart';
import '../application/suggestion_providers.dart';
import '../domain/comfort.dart';
import '../domain/suggestion.dart';
import 'suggestion_messages.dart';

/// "Sugestões para hoje" (incremento 5): conjuntos do motor com as razões,
/// o tempo usado e a ocasião. Escolher uma sugestão abre "Vesti hoje" com
/// as peças por confirmar; só guardar conta como uso (P-08).
class TodaySuggestionsCard extends ConsumerWidget {
  const TodaySuggestionsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final result = ref.watch(todaySuggestionsProvider);
    final choices = ref.watch(suggestionChoicesProvider);
    final notifier = ref.read(suggestionChoicesProvider.notifier);

    return Column(
      key: const Key('today-suggestions'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _WeatherLine(),
        const SizedBox(height: 22),
        Text(l10n.suggestionsTitle, style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        // Uma só linha que desliza: a ocasião não deve ocupar o ecrã.
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          child: Row(
            children: [
              for (final (o, key, label) in [
                (null, 'any', l10n.suggestionsAnyOccasion),
                for (final o in Occasion.values)
                  (o, o.id, l10n.occasionLabel(o.id)),
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    key: Key('suggestions-occasion-$key'),
                    showCheckmark: false,
                    label: Text(label),
                    selected: choices.occasion == o,
                    onSelected: (_) => notifier.occasion(o),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (result == null)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          )
        else
          _Result(result: result),
      ],
    );
  }
}

class _WeatherLine extends ConsumerWidget {
  const _WeatherLine();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final material = MaterialLocalizations.of(context);
    final choices = ref.watch(suggestionChoicesProvider);
    final notifier = ref.read(suggestionChoicesProvider.notifier);
    final manual = choices.manual;
    final lead = theme.textTheme.bodyLarge?.copyWith(
      height: 1.45,
      color: theme.colorScheme.onSurfaceVariant,
    );
    final small = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    if (manual != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.weatherManual(
              comfortBandText(l10n, manual.band),
              manual.rain ? 'yes' : 'no',
            ),
            key: const Key('weather-manual'),
            style: lead,
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final b in ComfortBand.values)
                ChoiceChip(
                  key: Key('weather-manual-${b.name}'),
                  label: Text(comfortBandText(l10n, b)),
                  selected: manual.band == b,
                  onSelected: (_) =>
                      notifier.manual(ManualWeather(b, rain: manual.rain)),
                ),
              FilterChip(
                key: const Key('weather-manual-rain'),
                label: Text(l10n.weatherRain),
                selected: manual.rain,
                onSelected: (rain) =>
                    notifier.manual(ManualWeather(manual.band, rain: rain)),
              ),
              TextButton(
                key: const Key('weather-manual-clear'),
                onPressed: () => notifier.manual(null),
                child: Text(l10n.weatherManualClear),
              ),
            ],
          ),
        ],
      );
    }

    final report = ref.watch(todayWeatherProvider);
    final manualButton = TextButton(
      key: const Key('weather-manual-set'),
      onPressed: () => notifier.manual(const ManualWeather(ComfortBand.mild)),
      child: Text(l10n.weatherManualSet),
    );
    final refreshButton = IconButton(
      key: const Key('weather-refresh'),
      tooltip: l10n.weatherRefresh,
      icon: const Icon(Icons.refresh, size: 20),
      onPressed: () => refreshTodayWeather(ref),
    );

    final value = report.value;
    if (value == null) {
      return Wrap(
        spacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          Text(l10n.weatherLoading, style: lead),
          manualButton,
        ],
      );
    }
    final weather = value.weather;
    if (weather == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.weatherNone(value.gap!.name),
            key: const Key('weather-none'),
            style: lead,
          ),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [refreshButton, manualButton],
          ),
        ],
      );
    }
    String n(double v) => v.round().toString();
    final fetched = value.fetchedAt!.toLocal();
    final when =
        '${material.formatShortDate(fetched)} '
        '${material.formatTimeOfDay(TimeOfDay.fromDateTime(fetched))}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.weatherSummary(
            value.location.name,
            n(weather.feelsLikeC),
            n(weather.feelsLikeMinC),
            n(weather.feelsLikeMaxC),
            weather.precipitationMm.toStringAsFixed(1),
            n(weather.windMaxKmh),
          ),
          key: const Key('weather-summary'),
          style: lead,
        ),
        const SizedBox(height: 2),
        Text(
          '${l10n.weatherFetched(value.freshness!.name, when)} · '
          '${l10n.weatherAttribution}',
          key: const Key('weather-fetched'),
          style: small?.copyWith(
            color: value.freshness == ForecastFreshness.stale
                ? AppColors.onCareSoft
                : null,
          ),
        ),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [refreshButton, manualButton],
        ),
      ],
    );
  }
}

/// Mostra uma sugestão de cada vez; "Mostrar outro" passa à seguinte e,
/// no fim, pede ao motor um novo lote.
class _Result extends ConsumerStatefulWidget {
  const _Result({required this.result});

  final SuggestionResult result;

  @override
  ConsumerState<_Result> createState() => _ResultState();
}

class _ResultState extends ConsumerState<_Result> {
  var _shown = 0;
  var _saving = false;

  static String _key(OutfitCandidate c) =>
      ([for (final i in c.items) i.garment.id.value]..sort()).join(',');

  @override
  void didUpdateWidget(_Result old) {
    super.didUpdateWidget(old);
    // A mesma sugestão continua à vista se só mudou de lugar (ex.: depois
    // de a guardar como conjunto).
    final before = old.result.candidates;
    if (_shown < before.length) {
      final key = _key(before[_shown]);
      final now = widget.result.candidates.indexWhere((c) => _key(c) == key);
      if (now >= 0) {
        _shown = now;
        return;
      }
    }
    if (_shown >= widget.result.candidates.length) _shown = 0;
  }

  /// Guarda as peças da sugestão (sem a camada opcional) como conjunto,
  /// com a ocasião escolhida.
  Future<void> _save(OutfitCandidate candidate) async {
    final repo = ref.read(outfitRepositoryProvider);
    if (repo == null) return;
    final occasion = ref.read(suggestionChoicesProvider).occasion;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    final result = await repo.createOutfit(
      OutfitDraft(items: candidate.outfitItems, occasions: {?occasion}),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (!reportOutfit(context, result)) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l10n.suggestionsOutfitSaved)));
  }

  void _next() {
    if (_shown + 1 < widget.result.candidates.length) {
      setState(() => _shown++);
    } else {
      setState(() => _shown = 0);
      ref.read(suggestionChoicesProvider.notifier).reshuffle();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final result = widget.result;
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
    return switch (result.status) {
      SuggestionStatus.insufficientData => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          l10n.suggestionsInsufficient,
          key: const Key('suggestions-insufficient'),
          style: muted,
        ),
      ),
      SuggestionStatus.notFound => Column(
        key: const Key('suggestions-not-found'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.suggestionsNotFound, style: muted),
          ...gaps,
        ],
      ),
      SuggestionStatus.valid || SuggestionStatus.partial => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CandidateView(
            index: _shown,
            total: result.candidates.length,
            candidate: result.candidates[_shown],
          ),
          ...gaps,
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton(
                key: Key('suggestion-$_shown-wear'),
                onPressed: () => context.push(
                  AppRoutes.wearWith([
                    for (final i in result.candidates[_shown].items)
                      i.garment.id.value,
                  ]),
                ),
                child: Text(l10n.suggestionsWearThis),
              ),
              TextButton(
                key: const Key('suggestions-more'),
                onPressed: _next,
                child: Text(l10n.suggestionsShowAnother),
              ),
              // Uma variante com peça trocada pode guardar-se como outro.
              if (!result.candidates[_shown].notes.any(
                (n) => n is SavedOutfitNote && n.swaps.isEmpty,
              ))
                TextButton.icon(
                  key: Key('suggestion-$_shown-save'),
                  onPressed: _saving
                      ? null
                      : () => _save(result.candidates[_shown]),
                  icon: const Icon(Icons.bookmark_add_outlined),
                  label: Text(l10n.suggestionsSaveOutfit),
                ),
            ],
          ),
        ],
      ),
    };
  }
}

/// A sugestão como um flat-lay: as peças pousadas no papel, os nomes numa
/// frase e as razões escondidas até se pedirem (os avisos ficam à vista).
class _CandidateView extends StatefulWidget {
  const _CandidateView({
    required this.index,
    required this.total,
    required this.candidate,
  });

  final int index;
  final int total;
  final OutfitCandidate candidate;

  @override
  State<_CandidateView> createState() => _CandidateViewState();
}

class _CandidateViewState extends State<_CandidateView> {
  var _why = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final candidate = widget.candidate;
    final index = widget.index;
    final layer = candidate.optionalLayer;
    final items = [...candidate.items, ?layer];
    final small = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      height: 1.45,
    );
    const warn = TextStyle(color: AppColors.onCareSoft);

    final warnings = <Widget>[
      for (final note in candidate.notes)
        if (note is MissingRole)
          if (noteText(context, note) case final text?)
            Text(text, style: small?.merge(warn)),
      for (final item in items)
        for (final n in item.notes.where(SuggestedItem.isWarning))
          if (noteText(context, n) case final text?)
            Text(
              '${garmentLabel(l10n, item.garment)}: $text',
              style: small?.merge(warn),
            ),
    ];
    final reasons = <Widget>[
      for (final note in candidate.notes)
        if (note is! MissingRole && note is! SavedOutfitNote)
          if (noteText(context, note) case final text?)
            Text(text, style: small),
      for (final item in items)
        if ([
              for (final n in item.notes)
                if (!SuggestedItem.isWarning(n)) ?noteText(context, n),
            ]
            case final texts when texts.isNotEmpty)
          Text(
            '${garmentLabel(l10n, item.garment)} '
            '(${l10n.outfitRoleLabel(item.role.id).toLowerCase()}): '
            '${texts.join(' · ')}',
            style: small,
          ),
    ];

    return Column(
      key: Key('suggestion-$index'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FlatLay(items: items),
        Text(
          l10n.suggestionOf('${index + 1}', '${widget.total}'),
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          [for (final i in candidate.items) garmentLabel(l10n, i.garment)]
              .join(', '),
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        if (layer != null)
          Text(
            l10n.suggestionsOptionalLayer(garmentLabel(l10n, layer.garment)),
            style: small,
          ),
        for (final note in candidate.notes.whereType<SavedOutfitNote>())
          if (noteText(context, note) case final text?)
            Text(
              text,
              key: Key('suggestion-$index-saved'),
              style: small?.copyWith(color: theme.colorScheme.primary),
            ),
        ...warnings,
        if (reasons.isNotEmpty) ...[
          if (_why) ...[const SizedBox(height: 4), ...reasons],
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: Key('suggestion-$index-why'),
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 36),
              ),
              onPressed: () => setState(() => _why = !_why),
              child: Text(_why ? l10n.suggestionsWhyHide : l10n.suggestionsWhy),
            ),
          ),
        ],
      ],
    );
  }
}

/// Até quatro peças em posições fixas e ligeiramente rodadas; a ordem do
/// motor (parte de cima, de baixo, calçado, camada) decide o lugar.
class _FlatLay extends StatelessWidget {
  const _FlatLay({required this.items});

  final List<SuggestedItem> items;

  // (x, y, tamanho, rotação) em frações da largura.
  static const _slots = [
    (0.04, 0.04, 0.42, -0.10),
    (0.50, 0.02, 0.40, 0.08),
    (0.30, 0.40, 0.34, -0.04),
    (0.70, 0.46, 0.27, 0.12),
    (0.02, 0.50, 0.26, 0.06),
  ];

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final w = constraints.maxWidth.clamp(0, 420).toDouble();
      final shown = items.take(_slots.length).toList();
      return SizedBox(
        width: w,
        height: w * 0.80,
        child: Stack(
          children: [
            for (final (i, item) in shown.indexed)
              Positioned(
                left: w * _slots[i].$1,
                top: w * _slots[i].$2,
                child: Semantics(
                  label: garmentLabel(
                    AppLocalizations.of(context),
                    item.garment,
                  ),
                  child: GarmentCutout(
                    garment: item.garment,
                    size: w * _slots[i].$3,
                    angle: _slots[i].$4,
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}
