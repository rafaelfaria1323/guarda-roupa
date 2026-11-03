import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/domain/clock.dart';
import '../../account_sync/application/providers.dart';
import '../data/powersync_wear_repository.dart';
import '../domain/calendar_day.dart';
import '../domain/wear_repository.dart';

/// Substituído nos testes para fixar "hoje".
final clockProvider = Provider<Clock>((ref) => const SystemClock());

/// O dia de hoje no fuso do dispositivo.
CalendarDay todayFrom(Clock clock) => CalendarDay.of(clock.nowUtc());

final wearRepositoryProvider = Provider<WearRepository?>((ref) {
  final user = ref.watch(currentUserProvider).value;
  final db = ref.watch(userDatabaseProvider).value;
  if (user == null || db == null) return null;
  return PowerSyncWearRepository(
    db: db,
    ownerId: user.id,
    clock: ref.watch(clockProvider),
  );
});
