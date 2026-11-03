import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../account_sync/application/providers.dart';
import '../../wear/application/wear_providers.dart';
import '../data/powersync_outfit_repository.dart';
import '../domain/outfit.dart';
import '../domain/outfit_repository.dart';

final outfitRepositoryProvider = Provider<OutfitRepository?>((ref) {
  final user = ref.watch(currentUserProvider).value;
  final db = ref.watch(userDatabaseProvider).value;
  if (user == null || db == null) return null;
  return PowerSyncOutfitRepository(
    db: db,
    ownerId: user.id,
    clock: ref.watch(clockProvider),
  );
});

final outfitsProvider = StreamProvider<List<Outfit>>((ref) {
  final repo = ref.watch(outfitRepositoryProvider);
  return repo == null ? const Stream.empty() : repo.watchOutfits();
});
