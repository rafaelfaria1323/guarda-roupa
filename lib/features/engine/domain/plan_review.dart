import '../../outfits/domain/outfit.dart';
import '../../wardrobe/domain/availability.dart';
import '../../wardrobe/domain/garment.dart';
import '../../wardrobe/domain/garment_attributes.dart';
import '../../wear/domain/calendar_day.dart';
import '../../wear/domain/wear_event.dart';
import 'comfort.dart';
import 'daily_engine.dart';
import 'suggestion.dart';

/// Porque uma peça planeada deixou de servir para o dia.
sealed class PlanIssue {
  const PlanIssue(this.item);
  final OutfitItem item;
}

/// Arquivada ou eliminada.
final class GarmentGone extends PlanIssue {
  const GarmentGone(super.item);
}

/// Suja, a lavar ou a secar: não se presume que esteja pronta.
final class GarmentUnavailable extends PlanIssue {
  const GarmentUnavailable(super.item, this.availability);
  final Availability availability;
}

/// Utilizações reais desde a última limpeza já pedem lavagem (P-07).
final class WashDue extends PlanIssue {
  const WashDue(super.item, this.uses, this.threshold);
  final int uses;
  final int threshold;
}

/// A previsão atual não combina com o aquecimento da peça.
final class ComfortUnsuited extends PlanIssue {
  const ComfortUnsuited(super.item, this.band);
  final ComfortBand band;
}

/// O frio previsto pede um casaco por cima de [item] e o dia não tem.
final class OuterLayerNeeded extends PlanIssue {
  const OuterLayerNeeded(super.item);
}

/// Calçado ou casaco que não é para a chuva ou o vento previstos.
final class WeatherUnsuited extends PlanIssue {
  const WeatherUnsuited(super.item, {required this.rain});
  final bool rain;
}

/// Um dia do plano, tal como está.
final class ReviewDay {
  const ReviewDay({
    required this.day,
    required this.items,
    this.occasion,
    this.weather,
    this.reviewable = true,
  });

  final CalendarDay day;
  final List<OutfitItem> items;
  final Occasion? occasion;
  final WeatherConditions? weather;

  /// `false`: confirmado ou passado; não se revê nem conta como reserva.
  final bool reviewable;
}

final class DayReview {
  const DayReview({required this.day, this.issues = const [], this.proposal});

  final CalendarDay day;
  final List<PlanIssue> issues;

  /// Só as peças com problemas mudam; `null` se o dia está bem.
  final Replacement? proposal;

  bool get affected => issues.isNotEmpty;
}

/// Mudanças posteriores (docs/features/planeamento-semanal.md): identifica
/// os dias afetados, diz porquê e propõe substituições só das peças com
/// problemas. Nunca reescreve o plano: aplicar é uma decisão do utilizador.
///
/// As substituições veem as reservas dos dias anteriores (como a pesquisa
/// semanal); os problemas veem só o estado real.
abstract final class PlanReview {
  static List<DayReview> review(
    WardrobeSnapshot snapshot,
    List<ReviewDay> days, {
    ComfortThresholds comfort = const ComfortThresholds(),
    int seed = 0,
  }) {
    final byId = {for (final g in snapshot.garments) g.id: g};
    final projected = <WearEvent>[];
    final out = <DayReview>[];
    for (final (index, d) in days.indexed) {
      if (!d.reviewable || d.items.isEmpty) {
        out.add(DayReview(day: d.day));
        continue;
      }
      SuggestionRequest request(int salt) => SuggestionRequest(
        day: d.day,
        occasion: d.occasion,
        weather: d.weather,
        comfort: comfort,
        seed: seed + salt,
      );
      final assessed = DailyEngine.assess(snapshot, request(index), d.items);
      final hasOuter = d.items.any((i) => i.role == OutfitRole.outerLayer);
      final issues = [
        for (final (i, item) in d.items.indexed)
          ..._issues(item, byId[item.garmentId], assessed[i]),
      ];
      if (!hasOuter) {
        for (final (i, a) in assessed.indexed) {
          if (a == null || !_upperBody.contains(a.role)) continue;
          if (a.notes.any(
            (n) => n is ComfortNote && n.fit == ComfortFit.fitsWithOuterLayer,
          )) {
            issues.add(OuterLayerNeeded(d.items[i]));
          }
        }
      }
      Replacement? proposal;
      if (issues.isNotEmpty) {
        proposal = DailyEngine.replace(
          snapshot.withWears([...snapshot.wears, ...projected]),
          request(index),
          d.items,
          replace: {
            for (final i in issues)
              if (i is! OuterLayerNeeded) i.item.garmentId,
          },
          add: {
            if (issues.any((i) => i is OuterLayerNeeded)) OutfitRole.outerLayer,
          },
        );
      }
      out.add(DayReview(day: d.day, issues: issues, proposal: proposal));
      final kept = proposal?.items ?? d.items;
      if (kept.isNotEmpty) {
        projected.add(
          WearEvent(
            id: 'projected:${d.day.iso}',
            wornOn: d.day,
            garmentIds: [for (final i in kept) i.garmentId],
            createdAt: d.day.toLocalDateTime().toUtc(),
          ),
        );
      }
    }
    return out;
  }

  static const _upperBody = {OutfitRole.mainTop, OutfitRole.onePiece};

  static Iterable<PlanIssue> _issues(
    OutfitItem item,
    Garment? garment,
    SuggestedItem? assessed,
  ) sync* {
    if (garment == null || garment.isArchived || assessed == null) {
      yield GarmentGone(item);
      return;
    }
    if (!garment.availability.isAvailable) {
      yield GarmentUnavailable(item, garment.availability);
      return;
    }
    for (final n in assessed.notes) {
      switch (n) {
        case WashRecommended(:final uses, :final threshold):
          yield WashDue(item, uses, threshold);
        case ComfortNote(fit: ComfortFit.mismatch, :final band):
          yield ComfortUnsuited(item, band);
        case WeatherFlagNote(ok: false, :final rain):
          yield WeatherUnsuited(item, rain: rain);
        default:
          break;
      }
    }
  }
}
