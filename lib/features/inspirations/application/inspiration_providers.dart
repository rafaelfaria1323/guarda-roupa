import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../account_sync/application/providers.dart';
import '../../wear/application/wear_providers.dart';
import '../data/powersync_inspiration_repository.dart';
import '../domain/inspiration.dart';
import '../domain/inspiration_repository.dart';

final inspirationRepositoryProvider = Provider<InspirationRepository?>((ref) {
  final user = ref.watch(currentUserProvider).value;
  final db = ref.watch(userDatabaseProvider).value;
  if (user == null || db == null) return null;
  return PowerSyncInspirationRepository(
    db: db,
    ownerId: user.id,
    clock: ref.watch(clockProvider),
  );
});

final inspirationsProvider = StreamProvider<List<Inspiration>>((ref) {
  final repo = ref.watch(inspirationRepositoryProvider);
  return repo == null ? const Stream.empty() : repo.watchInspirations();
});
