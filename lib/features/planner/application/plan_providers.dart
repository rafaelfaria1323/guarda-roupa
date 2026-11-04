import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../account_sync/application/providers.dart';
import '../../wear/application/wear_providers.dart';
import '../../wear/domain/calendar_day.dart';
import '../data/powersync_plan_repository.dart';
import '../domain/plan_entry.dart';
import '../domain/plan_repository.dart';

final planRepositoryProvider = Provider<PlanRepository?>((ref) {
  final user = ref.watch(currentUserProvider).value;
  final db = ref.watch(userDatabaseProvider).value;
  if (user == null || db == null) return null;
  return PowerSyncPlanRepository(
    db: db,
    ownerId: user.id,
    clock: ref.watch(clockProvider),
  );
});

/// As entradas dos 7 dias a partir de [from] (dias sem entrada ficam de
/// fora: o ponto de partida é `PlanDraft.defaultFor`).
final weekPlanProvider = StreamProvider.family<List<PlanEntry>, CalendarDay>((
  ref,
  from,
) {
  final repo = ref.watch(planRepositoryProvider);
  return repo == null
      ? const Stream.empty()
      : repo.watchDays(from, days: WeekPlanRules.days);
});
