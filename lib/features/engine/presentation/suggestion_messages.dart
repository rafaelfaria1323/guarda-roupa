import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../inspirations/domain/style_preference.dart';
import '../../inspirations/presentation/preference_messages.dart';
import '../../wear/presentation/today_wear_card.dart';
import '../domain/comfort.dart';
import '../domain/suggestion.dart';

/// Texto curto de uma nota (`null` = não vale a pena mostrar).
String? noteText(BuildContext context, SuggestionNote note) {
  final l10n = AppLocalizations.of(context);
  final material = MaterialLocalizations.of(context);
  String date(DateTime d) => material.formatShortDate(d);
  return switch (note) {
    OccasionUnknown() => l10n.noteOccasionUnknown,
    OccasionMatches(:final occasion) => l10n.noteOccasionMatches(
      l10n.occasionLabel(occasion.id),
    ),
    ComfortNote(:final fit) => l10n.noteComfort(fit.name),
    WeatherFlagNote(:final rain, :final ok) => l10n.noteWeatherFlag(
      rain ? 'rain' : 'wind',
      switch (ok) {
        true => 'yes',
        false => 'no',
        null => 'unknown',
      },
    ),
    RotationExceeded(:final lastWornOn, :final eligibleFrom) =>
      l10n.noteRotationExceeded(
        date(lastWornOn.toLocalDateTime()),
        date(eligibleFrom.toLocalDateTime()),
      ),
    NeverWorn() => l10n.noteNeverWorn,
    RecentUses(:final times) => l10n.noteRecentUses(times),
    WashRecommended() => l10n.noteWash,
    PreferenceMatch(:final preference) => preferenceTitle(l10n, preference),
    ColorCombosNote(:final combos) => l10n.noteColorCombos(
      [
        for (final c in StyleCombo.values)
          if (combos.contains(c)) l10n.comboLabel(c.id),
      ].join(' · '),
    ),
    SurfaceMixNote(:final patterned, :final textured) => l10n.noteSurfaceMix(
      switch ((patterned > 1, textured > 1)) {
        (true, true) => 'both',
        (true, false) => 'patterns',
        _ => 'textures',
      },
    ),
    FormalityMixNote() => l10n.noteFormalityMix,
    OptionalLayerNote() => l10n.noteOptionalLayer,
    SavedOutfitNote(:final outfit, swaps: []) => switch (outfit.name) {
      final name? => l10n.noteSavedOutfit(name),
      null => l10n.noteSavedOutfitUnnamed,
    },
    SavedOutfitNote(:final outfit, :final swaps) => () {
      final added = [for (final s in swaps) garmentLabel(l10n, s.added)];
      final removed = [
        for (final s in swaps)
          switch (s.removed) {
            final g? => garmentLabel(l10n, g),
            null => l10n.noteSavedOutfitGone,
          },
      ];
      return switch (outfit.name) {
        final name? => l10n.noteSavedOutfitSwap(
          name,
          added.join(', '),
          removed.join(', '),
        ),
        null => l10n.noteSavedOutfitSwapUnnamed(
          added.join(', '),
          removed.join(', '),
        ),
      };
    }(),
    MissingRole(:final role) => l10n.suggestionsMissing(
      l10n.outfitRoleLabel(role.id),
    ),
    NoWeather() => null,
  };
}

String comfortBandText(AppLocalizations l10n, ComfortBand band) =>
    l10n.comfortBandLabel(band.name);
