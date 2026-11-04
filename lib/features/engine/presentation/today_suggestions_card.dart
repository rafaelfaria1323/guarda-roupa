import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../l10n/app_localizations.dart';
import '../../wardrobe/domain/garment_attributes.dart';
import '../../wardrobe/presentation/garment_photo_view.dart';
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

    return Card(
      key: const Key('today-suggestions'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.suggestionsTitle, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(l10n.suggestionsHint, style: theme.textTheme.bodySmall),
            const SizedBox(height: 12),
            const _WeatherLine(),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                ChoiceChip(
                  key: const Key('suggestions-occasion-any'),
                  label: Text(l10n.suggestionsAnyOccasion),
                  selected: choices.occasion == null,
                  onSelected: (_) => notifier.occasion(null),
                ),
                for (final o in Occasion.values)
                  ChoiceChip(
                    key: Key('suggestions-occasion-${o.id}'),
                    label: Text(l10n.occasionLabel(o.id)),
                    selected: choices.occasion == o,
                    onSelected: (_) => notifier.occasion(o),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (result == null)
              const Center(child: CircularProgressIndicator())
            else
              _Result(result: result),
          ],
        ),
      ),
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
    final manualButton = TextButton.icon(
      key: const Key('weather-manual-set'),
      onPressed: () => notifier.manual(const ManualWeather(ComfortBand.mild)),
      icon: const Icon(Icons.edit_outlined),
      label: Text(l10n.weatherManualSet),
    );
    final refreshButton = IconButton(
      key: const Key('weather-refresh'),
      tooltip: l10n.weatherRefresh,
      icon: const Icon(Icons.refresh),
      onPressed: () => refreshTodayWeather(ref),
    );

    final value = report.value;
    if (value == null) {
      return Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [Text(l10n.weatherLoading), manualButton],
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
        ),
        Text(
          '${l10n.weatherFetched(value.freshness!.name, when)} · '
          '${l10n.weatherAttribution}',
          key: const Key('weather-fetched'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: value.freshness == ForecastFreshness.stale
                ? theme.colorScheme.error
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

class _Result extends ConsumerWidget {
  const _Result({required this.result});

  final SuggestionResult result;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final gaps = [
      for (final g in result.gaps)
        Text(
          l10n.suggestionsGap(l10n.outfitRoleLabel(g.role.id), g.cause.name),
        ),
    ];
    return switch (result.status) {
      SuggestionStatus.insufficientData => Text(
        l10n.suggestionsInsufficient,
        key: const Key('suggestions-insufficient'),
      ),
      SuggestionStatus.notFound => Column(
        key: const Key('suggestions-not-found'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [Text(l10n.suggestionsNotFound), ...gaps],
      ),
      SuggestionStatus.valid || SuggestionStatus.partial => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (i, c) in result.candidates.indexed)
            _CandidateTile(index: i, candidate: c),
          ...gaps,
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              key: const Key('suggestions-more'),
              onPressed: () =>
                  ref.read(suggestionChoicesProvider.notifier).reshuffle(),
              icon: const Icon(Icons.shuffle),
              label: Text(l10n.suggestionsMore),
            ),
          ),
        ],
      ),
    };
  }
}

class _CandidateTile extends StatelessWidget {
  const _CandidateTile({required this.index, required this.candidate});

  final int index;
  final OutfitCandidate candidate;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final layer = candidate.optionalLayer;
    return Padding(
      key: Key('suggestion-$index'),
      padding: const EdgeInsets.only(bottom: 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  l10n.suggestionNumber('${index + 1}'),
                  style: theme.textTheme.titleSmall,
                ),
              ),
              for (final item in candidate.items) _ItemRow(item: item),
              for (final note in candidate.notes)
                if (noteText(context, note) case final text?)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      text,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
              if (layer != null)
                _ItemRow(
                  item: layer,
                  title: l10n.suggestionsOptionalLayer(
                    garmentLabel(l10n, layer.garment),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: TextButton.icon(
                  key: Key('suggestion-$index-wear'),
                  onPressed: () => context.push(
                    AppRoutes.wearWith([
                      for (final i in candidate.items) i.garment.id.value,
                    ]),
                  ),
                  icon: const Icon(Icons.check),
                  label: Text(l10n.suggestionsWearThis),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item, this.title});

  final SuggestedItem item;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final notes = <InlineSpan>[];
    for (final n in item.notes) {
      final text = noteText(context, n);
      if (text == null) continue;
      notes.add(
        TextSpan(
          text: ' · $text',
          style: SuggestedItem.isWarning(n)
              ? TextStyle(color: theme.colorScheme.error)
              : null,
        ),
      );
    }
    final photos = item.garment.photos;
    return ListTile(
      dense: true,
      leading: SizedBox.square(
        dimension: 40,
        child: photos.isEmpty
            ? const Icon(Icons.image_not_supported_outlined)
            : GarmentPhotoView(photo: photos.first, size: 40),
      ),
      title: Text(title ?? garmentLabel(l10n, item.garment)),
      subtitle: Text.rich(
        TextSpan(text: l10n.outfitRoleLabel(item.role.id), children: notes),
      ),
    );
  }
}
