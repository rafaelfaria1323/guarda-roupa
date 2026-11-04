import '../../care/domain/care_policies.dart';
import '../../care/domain/cleaning_event.dart';
import '../../inspirations/domain/style_preference.dart';
import '../../outfits/domain/outfit.dart';
import '../../wardrobe/domain/garment.dart';
import '../../wardrobe/domain/garment_attributes.dart';
import '../../wear/domain/calendar_day.dart';
import '../../wear/domain/wear_event.dart';
import 'comfort.dart';

/// O que o motor sabe do guarda-roupa: só peças que existem e histórico
/// confirmado. Inspirações nunca entram como peças.
final class WardrobeSnapshot {
  const WardrobeSnapshot({
    required this.garments,
    this.wears = const [],
    this.cleanings = const [],
    this.policies = const CarePolicies(),
    this.preferences = const [],
  });

  final List<Garment> garments;
  final List<WearEvent> wears;
  final List<CleaningEvent> cleanings;
  final CarePolicies policies;
  final List<StylePreference> preferences;
}

final class SuggestionRequest {
  const SuggestionRequest({
    required this.day,
    this.occasion,
    this.weather,
    this.comfort = const ComfortThresholds(),
    this.seed = 0,
    this.maxResults = 3,
  });

  final CalendarDay day;

  /// `null` = sem ocasião escolhida (nada é excluído por ocasião).
  final Occasion? occasion;

  /// `null` = sem previsão nem contexto manual: não há regras de conforto e
  /// o resultado diz isso.
  final WeatherConditions? weather;
  final ComfortThresholds comfort;

  /// Desempate controlável: o mesmo snapshot, pedido e seed dão o mesmo
  /// resultado.
  final int seed;
  final int maxResults;
}

/// Estado da pesquisa (docs/features/motor-de-combinacoes.md §6).
enum SuggestionStatus {
  /// Pelo menos um conjunto completo.
  valid,

  /// Só conjuntos a que falta um papel (calçado, ou casaco no frio).
  partial,

  /// Há peças, mas nenhuma serve para hoje (indisponíveis, ocasião, …).
  notFound,

  /// O guarda-roupa não tem as peças necessárias para nenhum modelo.
  insufficientData,
}

/// Uma explicação legível, traduzida na apresentação.
sealed class SuggestionNote {
  const SuggestionNote();
}

/// A peça não tem ocasiões indicadas; pode não servir para a pedida.
final class OccasionUnknown extends SuggestionNote {
  const OccasionUnknown();
}

final class OccasionMatches extends SuggestionNote {
  const OccasionMatches(this.occasion);
  final Occasion occasion;
}

final class ComfortNote extends SuggestionNote {
  const ComfortNote(this.fit, this.band, this.warmth);
  final ComfortFit fit;
  final ComfortBand band;
  final Warmth? warmth;
}

/// Chuva ou vento: a peça está (ou não, ou não se sabe) marcada como
/// adequada.
final class WeatherFlagNote extends SuggestionNote {
  const WeatherFlagNote({required this.rain, required this.ok});
  final bool rain;

  /// `null` = não se sabe.
  final bool? ok;
}

/// Ainda dentro do intervalo de rotatividade (P-06): não havia alternativa
/// elegível para este papel.
final class RotationExceeded extends SuggestionNote {
  const RotationExceeded({
    required this.lastWornOn,
    required this.eligibleFrom,
  });
  final CalendarDay lastWornOn;
  final CalendarDay eligibleFrom;
}

final class NeverWorn extends SuggestionNote {
  const NeverWorn();
}

/// Usada [times] vezes nos últimos [RotationPolicy.recentWindowDays] dias.
final class RecentUses extends SuggestionNote {
  const RecentUses(this.times, this.lastWornOn);
  final int times;
  final CalendarDay lastWornOn;
}

/// Informativo (P-07): não impede a sugestão.
final class WashRecommended extends SuggestionNote {
  const WashRecommended(this.uses, this.threshold);
  final int uses;
  final int threshold;
}

final class PreferenceMatch extends SuggestionNote {
  const PreferenceMatch(this.preference);
  final StylePreference preference;
}

/// Notas do conjunto.
final class MissingRole extends SuggestionNote {
  const MissingRole(this.role);
  final OutfitRole role;
}

/// Sem previsão: não se aplicaram regras de conforto.
final class NoWeather extends SuggestionNote {
  const NoWeather();
}

/// Combinações de cor que o conjunto cumpre (P-21), só descritas: as que
/// o utilizador prefere ou evita aparecem como [PreferenceMatch].
final class ColorCombosNote extends SuggestionNote {
  const ColorCombosNote(this.combos);
  final Set<StyleCombo> combos;
}

/// Mais de um padrão, ou mais de uma textura forte: ficam a competir. Só
/// põe o conjunto atrás de outro igual em tudo o resto.
final class SurfaceMixNote extends SuggestionNote {
  const SurfaceMixNote({required this.patterned, required this.textured});
  final int patterned;
  final int textured;
}

/// Ameno: pode juntar-se esta camada, se quiser.
final class OptionalLayerNote extends SuggestionNote {
  const OptionalLayerNote();
}

final class SuggestedItem {
  const SuggestedItem(this.garment, this.role, this.notes);

  final Garment garment;
  final OutfitRole role;
  final List<SuggestionNote> notes;

  /// Notas que pedem atenção (não impedem a sugestão).
  Iterable<SuggestionNote> get warnings => notes.where(isWarning);

  static bool isWarning(SuggestionNote n) => switch (n) {
    RotationExceeded() || WashRecommended() || OccasionUnknown() => true,
    ComfortNote(:final fit) => fit == ComfortFit.mismatch,
    WeatherFlagNote(:final ok) => ok == false,
    PreferenceMatch(:final preference) =>
      preference.stance == PreferenceStance.avoid,
    _ => false,
  };
}

final class OutfitCandidate {
  const OutfitCandidate({
    required this.items,
    this.optionalLayer,
    this.notes = const [],
  });

  /// Pela ordem das camadas, sem a camada opcional.
  final List<SuggestedItem> items;

  /// Sugestão de camada que o utilizador pode juntar ou não.
  final SuggestedItem? optionalLayer;
  final List<SuggestionNote> notes;

  bool get isComplete => !notes.any((n) => n is MissingRole);

  /// Como item de conjunto (para guardar ou confirmar).
  List<OutfitItem> get outfitItems => [
    for (final i in items) OutfitItem(i.garment.id, i.role),
  ];
}

/// Porque um papel não tem candidatos.
enum GapCause {
  /// Não há peças desta categoria.
  none,

  /// Há, mas estão indisponíveis ou arquivadas.
  unavailable,

  /// Há disponíveis, mas indicadas para outras ocasiões.
  otherOccasions,
}

final class RoleGap {
  const RoleGap(this.role, this.cause);
  final OutfitRole role;
  final GapCause cause;
}

final class SuggestionResult {
  const SuggestionResult({
    required this.status,
    this.candidates = const [],
    this.gaps = const [],
    this.notes = const [],
  });

  final SuggestionStatus status;
  final List<OutfitCandidate> candidates;

  /// Papéis sem candidatos e porquê (para explicar sem inventar).
  final List<RoleGap> gaps;

  /// Notas gerais (ex.: sem previsão).
  final List<SuggestionNote> notes;
}

/// Resultado de [DailyEngine.replace].
final class Replacement {
  const Replacement({
    required this.items,
    this.added = const [],
    this.dropped = const [],
  });

  /// O conjunto novo, pela ordem das camadas.
  final List<OutfitItem> items;

  /// Peças que entraram.
  final List<OutfitItem> added;

  /// Papéis que ficaram sem peça.
  final List<OutfitRole> dropped;
}
