import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/domain/result.dart';
import '../../../l10n/app_localizations.dart';
import '../../care/application/care_providers.dart';
import '../../engine/domain/weekly_planner.dart';
import '../../outfits/domain/outfit.dart';
import '../../wardrobe/domain/garment.dart';
import '../../wardrobe/domain/garment_attributes.dart';
import '../../wear/application/wear_providers.dart';
import '../../wear/presentation/today_wear_card.dart';
import '../application/plan_providers.dart';
import '../domain/plan_entry.dart';
import '../domain/plan_repository.dart';

/// "Esta semana" (incremento 6, P-19): um cartão por dia com a ocasião, se
/// é provisório, as peças e o estado. Planear a semana só propõe; aceitar
/// fixa o dia; só "Vesti hoje" conta como uso.
class WeekPlanCard extends ConsumerStatefulWidget {
  const WeekPlanCard({super.key});

  @override
  ConsumerState<WeekPlanCard> createState() => _WeekPlanCardState();
}

class _WeekPlanCardState extends ConsumerState<WeekPlanCard> {
  var _busy = false;

  Future<void> _generate() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    final outcome = await generateWeek(ref);
    if (!mounted) return;
    setState(() => _busy = false);
    final text = switch (outcome) {
      WeekNotReady() => l10n.weekNotReady,
      WeekGenerated(:final proposed, :final notFound) =>
        l10n.weekGenerated(proposed, notFound).trim(),
      WeekSaveFailed() => l10n.weekSaveFailed,
    };
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final view = ref.watch(weekViewProvider);
    final search = ref.watch(lastWeekSearchProvider);
    final searched = {for (final d in search?.days ?? <DayPlan>[]) d.day: d};

    return Card(
      key: const Key('week-plan'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.weekTitle, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(l10n.weekHint, style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              key: const Key('week-generate'),
              onPressed: _busy || view == null ? null : _generate,
              icon: const Icon(Icons.auto_awesome_outlined),
              label: Text(l10n.weekGenerate),
            ),
            const SizedBox(height: 8),
            if (view == null)
              const Center(child: CircularProgressIndicator())
            else
              for (final (i, d) in view.indexed)
                _DayTile(index: i, view: d, search: searched[d.day]),
          ],
        ),
      ),
    );
  }
}

class _DayTile extends ConsumerWidget {
  const _DayTile({required this.index, required this.view, this.search});

  final int index;
  final WeekDayView view;
  final DayPlan? search;

  Future<void> _save(
    BuildContext context,
    WidgetRef ref,
    PlanDraft draft,
  ) async {
    final repo = ref.read(planRepositoryProvider);
    if (repo == null) return;
    final result = await repo.saveDay(view.day, draft);
    if (result is Err<PlanEntry, PlanFailure> && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).weekSaveFailed)),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final today = todayFrom(ref.watch(clockProvider));
    final garments = {
      for (final g in ref.watch(allGarmentsProvider).value ?? <Garment>[])
        g.id: g,
    };
    final entry = view.entry;
    final draft = view.draft;
    final state = view.state;
    final editable =
        state != PlanDayState.confirmed && state != PlanDayState.unused;
    String names(List<OutfitItem> items) =>
        [for (final i in items) garmentLabel(l10n, garments[i.garmentId])]
            .join(' · ');
    PlanDraft with_({
      Occasion? occasion,
      bool changeOccasion = false,
      bool? tentative,
      List<OutfitItem>? items,
      PlanStatus? status,
    }) => PlanDraft(
      occasion: changeOccasion ? occasion : draft.occasion,
      tentative: tentative ?? draft.tentative,
      items: items ?? draft.items,
      status: status ?? draft.status,
    );

    final key = 'week-day-$index';
    return Padding(
      key: Key(key),
      padding: const EdgeInsets.only(top: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    view.day == today
                        ? '${l10n.weekToday} · '
                              '${l10n.weekDay(view.day.toLocalDateTime())}'
                        : l10n.weekDay(view.day.toLocalDateTime()),
                    style: theme.textTheme.titleSmall,
                  ),
                  Text(
                    l10n.weekState(state?.name ?? 'none'),
                    key: Key('$key-state'),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              DropdownButton<Occasion?>(
                key: Key('$key-occasion'),
                isExpanded: true,
                value: view.occasion,
                onChanged: editable
                    ? (o) => _save(
                        context,
                        ref,
                        with_(occasion: o, changeOccasion: true),
                      )
                    : null,
                items: [
                  DropdownMenuItem(child: Text(l10n.weekOccasionUndecided)),
                  for (final o in Occasion.values)
                    DropdownMenuItem(
                      value: o,
                      child: Text(l10n.occasionLabel(o.id)),
                    ),
                ],
              ),
              FilterChip(
                key: Key('$key-tentative'),
                label: Text(l10n.weekTentative),
                selected: view.tentative,
                onSelected: editable
                    ? (v) => _save(context, ref, with_(tentative: v))
                    : null,
              ),
              const SizedBox(height: 4),
              if (draft.items.isNotEmpty)
                Text(names(draft.items), key: Key('$key-items'))
              else
                Text(
                  state == PlanDayState.accepted
                      ? l10n.weekLeftEmpty
                      : l10n.weekNothing,
                  key: Key('$key-items'),
                ),
              if (view.wear case final wear?)
                Text(
                  [
                    for (final id in wear.garmentIds)
                      garmentLabel(l10n, garments[id]),
                  ].join(' · '),
                  key: Key('$key-worn'),
                  style: theme.textTheme.bodySmall,
                ),
              if (search case final s?
                  when state == PlanDayState.proposed ||
                      s.status == DayPlanStatus.notFound) ...[
                if (s.repeats.isNotEmpty)
                  Text(
                    l10n.weekRepeats,
                    key: Key('$key-repeats'),
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                if (s.status == DayPlanStatus.notFound)
                  Text(
                    l10n.weekNotFound,
                    key: Key('$key-not-found'),
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
              ],
              if (entry?.proposal case final p?) ...[
                const SizedBox(height: 4),
                Text(l10n.weekProposal, key: Key('$key-proposal')),
                Text(
                  [
                    if (p.changesOccasion)
                      p.occasion == null
                          ? l10n.weekOccasionUndecided
                          : l10n.occasionLabel(p.occasion!.id),
                    if (p.tentative == true) l10n.weekTentative,
                    if (p.items case final items?)
                      items.isEmpty ? l10n.weekNothing : names(items),
                    if (p.status case final s?) l10n.weekState(s.id),
                  ].join(' · '),
                  style: theme.textTheme.bodySmall,
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton(
                      key: Key('$key-proposal-apply'),
                      onPressed: () => ref
                          .read(planRepositoryProvider)
                          ?.resolveProposal(entry!.id, accept: true),
                      child: Text(l10n.weekProposalApply),
                    ),
                    TextButton(
                      key: Key('$key-proposal-keep'),
                      onPressed: () => ref
                          .read(planRepositoryProvider)
                          ?.resolveProposal(entry!.id, accept: false),
                      child: Text(l10n.weekProposalKeep),
                    ),
                  ],
                ),
              ],
              Wrap(
                spacing: 8,
                children: [
                  if (editable && state == PlanDayState.proposed)
                    TextButton.icon(
                      key: Key('$key-accept'),
                      onPressed: () => _save(
                        context,
                        ref,
                        with_(status: PlanStatus.accepted),
                      ),
                      icon: const Icon(Icons.push_pin_outlined),
                      label: Text(l10n.weekAccept),
                    ),
                  if (editable && state == PlanDayState.accepted)
                    TextButton.icon(
                      key: Key('$key-reopen'),
                      onPressed: () => _save(
                        context,
                        ref,
                        with_(status: PlanStatus.proposed),
                      ),
                      icon: const Icon(Icons.edit_outlined),
                      label: Text(l10n.weekReopen),
                    ),
                  if (editable &&
                      view.tentative &&
                      !(state == PlanDayState.accepted && draft.items.isEmpty))
                    TextButton.icon(
                      key: Key('$key-leave-empty'),
                      onPressed: () => _save(
                        context,
                        ref,
                        with_(items: const [], status: PlanStatus.accepted),
                      ),
                      icon: const Icon(Icons.event_busy_outlined),
                      label: Text(l10n.weekLeaveEmpty),
                    ),
                  if (view.day == today &&
                      entry != null &&
                      draft.items.isNotEmpty &&
                      state != PlanDayState.confirmed)
                    TextButton.icon(
                      key: Key('$key-wear'),
                      onPressed: () => context.push(
                        AppRoutes.wearWith([
                          for (final i in draft.items) i.garmentId.value,
                        ], planEntryId: entry.id),
                      ),
                      icon: const Icon(Icons.check),
                      label: Text(l10n.weekWearThis),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
