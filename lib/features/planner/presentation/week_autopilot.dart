import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/domain/result.dart';
import '../../../l10n/app_localizations.dart';
import '../../engine/domain/plan_review.dart';
import '../../engine/domain/suggestion.dart';
import '../../wardrobe/domain/garment.dart';
import '../../care/application/care_providers.dart';
import '../../wear/domain/calendar_day.dart';
import '../application/plan_providers.dart';
import '../domain/plan_entry.dart';
import 'week_plan_card.dart';

/// Semana sozinha (decisão do utilizador a 2026-11-06): os dias por
/// planear enchem-se sozinhos, já aceites, e as trocas por uma peça suja ou
/// pelo tempo aplicam-se sozinhas, sempre com aviso e "Desfazer". Fica à
/// volta da app (não dentro do cartão da semana, que numa lista pode não
/// estar construído).
class WeekAutopilot extends ConsumerStatefulWidget {
  const WeekAutopilot({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<WeekAutopilot> createState() => _WeekAutopilotState();
}

class _WeekAutopilotState extends ConsumerState<WeekAutopilot> {
  var _autoBusy = false;

  @override
  void initState() {
    super.initState();
    // Depois do frame: não se mexe em providers enquanto se constroem.
    void later(Future<void> Function() action) =>
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(action());
        });
    ref.listenManual(
      autoPlanKeyProvider,
      (_, _) => later(() => _autoPlan(ref.read(autoPlanKeyProvider))),
      fireImmediately: true,
    );
    ref.listenManual(
      weekReviewProvider,
      (_, _) => later(() => _autoApply(ref.read(weekReviewProvider))),
      fireImmediately: true,
    );
  }

  /// Enche os dias por planear (uma tentativa por estado do guarda-roupa).
  Future<void> _autoPlan(String? key) async {
    if (key == null ||
        _autoBusy ||
        ref.read(weekPlanningBusyProvider) ||
        !ref.read(weekAutopilotEnabledProvider)) {
      return;
    }
    ref.read(autoPlanAttemptsProvider.notifier).add(key);
    _autoBusy = true;
    final WeekGeneration outcome;
    try {
      outcome = await generateWeek(ref, onlyEmpty: true);
    } on Object {
      // A app fechou a meio (a base fecha com ela): não há nada a avisar.
      if (!mounted) return;
      rethrow;
    } finally {
      _autoBusy = false;
    }
    if (!mounted) return;
    // O guarda-roupa pode ter mudado entretanto (a chave já tentada não
    // se repete).
    unawaited(_autoPlan(ref.read(autoPlanKeyProvider)));
    if (outcome case WeekGenerated(:final proposed) when proposed > 0) {
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.weekAutoPlanned(proposed))));
    }
  }

  /// Aplica as trocas com peça de substituição; o resto (sem alternativa)
  /// fica como aviso no cartão do dia, para o utilizador decidir.
  Future<void> _autoApply(Map<CalendarDay, DayReview>? reviews) async {
    final view = ref.read(weekViewProvider);
    if (reviews == null ||
        view == null ||
        !ref.read(weekAutopilotEnabledProvider)) {
      return;
    }
    final handled = ref.read(ignoredDayChangesProvider);
    final changes = <(WeekDayView, Replacement)>[];
    for (final d in view) {
      final p = reviews[d.day]?.proposal;
      if (p == null || p.added.isEmpty) continue;
      if (d.state != PlanDayState.proposed &&
          d.state != PlanDayState.accepted) {
        continue;
      }
      final key = dayChangeKey(d.day, p);
      if (handled.contains(key)) continue;
      ref.read(ignoredDayChangesProvider.notifier).ignore(key);
      changes.add((d, p));
    }
    if (changes.isEmpty) return;
    final repo = ref.read(planRepositoryProvider);
    if (repo == null) return;
    final applied = <(WeekDayView, Replacement)>[];
    for (final (d, p) in changes) {
      final draft = d.draft;
      final saved = await repo.saveDay(
        d.day,
        PlanDraft(
          occasion: draft.occasion,
          tentative: draft.tentative,
          items: p.items,
          status: draft.status,
        ),
      );
      if (saved is Ok) applied.add((d, p));
    }
    if (!mounted || applied.isEmpty) return;
    final l10n = AppLocalizations.of(context);
    final garments = {
      for (final g in ref.read(allGarmentsProvider).value ?? <Garment>[])
        g.id: g,
    };
    final lines = [
      for (final (d, p) in applied)
        l10n.weekAutoChanged(
          l10n.weekDay(d.day.toLocalDateTime()),
          dayChangeLines(
            l10n,
            d.draft.items,
            p,
            garments,
          ).map((l) => l.replaceFirst('· ', '')).join('; '),
        ),
    ];
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(lines.join('\n'), key: const Key('week-auto-changed')),
          duration: const Duration(seconds: 8),
          action: SnackBarAction(
            label: l10n.weekAutoUndo,
            onPressed: () async {
              for (final (d, _) in applied) {
                await repo.saveDay(d.day, d.draft);
              }
            },
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
