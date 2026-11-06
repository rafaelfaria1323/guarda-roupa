import '../../outfits/domain/outfit.dart';
import '../../wardrobe/domain/garment.dart';
import '../../wardrobe/domain/garment_attributes.dart';
import '../../wear/domain/calendar_day.dart';
import '../../wear/domain/wear_event.dart';
import 'comfort.dart';
import 'daily_engine.dart';
import 'suggestion.dart';

/// O que se sabe de um dia da semana a planear.
final class WeekDayRequest {
  const WeekDayRequest({
    required this.day,
    this.occasion,
    this.weather,
    this.pinned,
    this.include = true,
  });

  final CalendarDay day;
  final Occasion? occasion;
  final WeatherConditions? weather;

  /// Escolha fixada pelo utilizador: entra tal como está e conta como
  /// reserva para os outros dias.
  final List<OutfitItem>? pinned;

  /// `false`: o dia fica por planear (ex.: fim de semana provisório que o
  /// utilizador deixou vazio).
  final bool include;
}

final class WeekRequest {
  const WeekRequest({
    required this.days,
    this.comfort = const ComfortThresholds(),
    this.seed = 0,
    this.beamWidth = 8,
    this.candidatesPerDay = 5,
  });

  /// Por ordem cronológica.
  final List<WeekDayRequest> days;
  final ComfortThresholds comfort;
  final int seed;

  /// Quantas semanas parciais se mantêm em cada passo.
  final int beamWidth;

  /// Quantos conjuntos do motor diário se consideram por dia.
  final int candidatesPerDay;
}

enum DayPlanStatus {
  /// Conjunto escolhido pela pesquisa.
  planned,

  /// Escolha fixada, mantida.
  pinned,

  /// Fora da pesquisa por pedido.
  skipped,

  /// Nenhum conjunto possível nas regras atuais (ver [DayPlan.gaps]).
  notFound,
}

final class DayPlan {
  const DayPlan({
    required this.day,
    required this.status,
    this.candidate,
    this.pinned,
    this.repeats = const {},
    this.gaps = const [],
    this.notes = const [],
  });

  final CalendarDay day;
  final DayPlanStatus status;
  final OutfitCandidate? candidate;
  final List<OutfitItem>? pinned;

  /// Peças principais (top, parte de baixo, peça única) que já aparecem
  /// noutro dia desta semana. Permitido, mas identificado.
  final Set<GarmentId> repeats;
  final List<RoleGap> gaps;
  final List<SuggestionNote> notes;

  List<OutfitItem> get items =>
      pinned ?? candidate?.outfitItems ?? const <OutfitItem>[];
}

final class WeekPlanResult {
  const WeekPlanResult({
    required this.days,
    required this.explored,
    required this.beamWidth,
  });

  final List<DayPlan> days;

  /// Semanas parciais avaliadas (limite da pesquisa, não promessa de ótimo).
  final int explored;
  final int beamWidth;
}

/// Pesquisa semanal (docs/features/planeamento-semanal.md): beam search
/// cronológica sobre os candidatos do [DailyEngine].
///
/// - Os dias anteriores da semana parcial entram como **utilizações
///   projetadas** (reservas): a rotatividade de cada dia vê-as. Só servem
///   para planear; não são utilizações nem contam para a lavagem real.
/// - Roupa indisponível continua de fora: não se presume uma lavagem que
///   ainda não aconteceu.
/// - Cada semana parcial compara-se por ordem explícita, sem pesos:
///   papéis em falta, avisos (rotatividade, conforto, …), peças principais
///   repetidas, soma das posições no motor diário, seed.
/// - Com dias mais restritos (menos candidatos), a largura do beam evita
///   gastar cedo a única peça que outro dia precisava; não é ótimo global.
abstract final class WeeklyPlanner {
  static WeekPlanResult plan(WardrobeSnapshot snapshot, WeekRequest request) {
    var beam = <_State>[const _State.empty()];
    var explored = 0;
    final byId = {for (final g in snapshot.garments) g.id: g};

    for (final (index, dayRequest) in request.days.indexed) {
      final next = <_State>[];
      for (final state in beam) {
        if (!dayRequest.include) {
          next.add(
            state.extend(
              DayPlan(day: dayRequest.day, status: DayPlanStatus.skipped),
            ),
          );
          continue;
        }
        if (dayRequest.pinned case final pinned?) {
          next.add(
            state.extend(
              DayPlan(
                day: dayRequest.day,
                status: DayPlanStatus.pinned,
                pinned: pinned,
                repeats: state.repeatsOf(pinned, byId),
              ),
            ),
          );
          continue;
        }
        final result = DailyEngine.suggest(
          snapshot.withWears([...snapshot.wears, ...state.projected]),
          SuggestionRequest(
            day: dayRequest.day,
            occasion: dayRequest.occasion,
            weather: dayRequest.weather,
            comfort: request.comfort,
            seed: request.seed + index,
            maxResults: request.candidatesPerDay,
          ),
        );
        if (result.candidates.isEmpty) {
          next.add(
            state.extend(
              DayPlan(
                day: dayRequest.day,
                status: DayPlanStatus.notFound,
                gaps: result.gaps,
                notes: result.notes,
              ),
              missing: 1,
            ),
          );
          continue;
        }
        for (final (rank, c) in result.candidates.indexed) {
          explored++;
          final items = c.outfitItems;
          next.add(
            state.extend(
              DayPlan(
                day: dayRequest.day,
                status: DayPlanStatus.planned,
                candidate: c,
                repeats: state.repeatsOf(items, byId),
                gaps: result.gaps,
                notes: result.notes,
              ),
              missing: c.notes.whereType<MissingRole>().length,
              warnings: _warnings(c),
              rank: rank,
            ),
          );
        }
      }
      next.sort(_State.compare);
      beam = _distinct(next).take(request.beamWidth).toList();
    }

    return WeekPlanResult(
      days: beam.first.days,
      explored: explored,
      beamWidth: request.beamWidth,
    );
  }

  /// Avisos das peças (a camada opcional não conta: o utilizador decide).
  static int _warnings(OutfitCandidate c) =>
      c.items.fold(0, (n, i) => n + i.warnings.length);

  /// Semanas parciais iguais (mesmas peças nos mesmos dias) contam uma vez.
  static Iterable<_State> _distinct(List<_State> states) sync* {
    final seen = <String>{};
    for (final s in states) {
      if (seen.add(s.key)) yield s;
    }
  }
}

final class _State {
  const _State({
    required this.days,
    required this.projected,
    required this.missing,
    required this.warnings,
    required this.repeated,
    required this.ranks,
    required this.key,
  });

  const _State.empty()
    : days = const [],
      projected = const [],
      missing = 0,
      warnings = 0,
      repeated = 0,
      ranks = 0,
      key = '';

  final List<DayPlan> days;

  /// Utilizações projetadas dos dias já escolhidos (só para a pesquisa).
  final List<WearEvent> projected;
  final int missing;
  final int warnings;
  final int repeated;
  final int ranks;
  final String key;

  static const _mainRoles = {
    OutfitRole.mainTop,
    OutfitRole.bottom,
    OutfitRole.onePiece,
  };

  Set<GarmentId> repeatsOf(
    List<OutfitItem> items,
    Map<GarmentId, Garment> byId,
  ) {
    final before = {
      for (final d in days)
        for (final i in d.items)
          if (_mainRoles.contains(i.role)) i.garmentId,
    };
    return {
      for (final i in items)
        if (_mainRoles.contains(i.role) &&
            before.contains(i.garmentId) &&
            byId.containsKey(i.garmentId))
          i.garmentId,
    };
  }

  _State extend(
    DayPlan plan, {
    int missing = 0,
    int warnings = 0,
    int rank = 0,
  }) {
    final items = plan.items;
    return _State(
      days: [...days, plan],
      projected: [
        ...projected,
        if (items.isNotEmpty)
          WearEvent(
            id: 'projected:${plan.day.iso}',
            wornOn: plan.day,
            garmentIds: [for (final i in items) i.garmentId],
            createdAt: plan.day.toLocalDateTime().toUtc(),
          ),
      ],
      missing: this.missing + missing,
      warnings: this.warnings + warnings,
      repeated: repeated + plan.repeats.length,
      ranks: ranks + rank,
      key:
          '$key|${plan.day.iso}:'
          '${[for (final i in items) i.garmentId.value].join(',')}',
    );
  }

  static int compare(_State a, _State b) {
    for (final (x, y) in [
      (a.missing, b.missing),
      (a.warnings, b.warnings),
      (a.repeated, b.repeated),
      (a.ranks, b.ranks),
    ]) {
      if (x != y) return x.compareTo(y);
    }
    return a.key.compareTo(b.key);
  }
}
