import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../account_sync/application/providers.dart';
import '../../wardrobe/domain/garment.dart';
import '../../wardrobe/domain/garment_filter.dart';
import '../../wear/application/wear_providers.dart';
import '../data/powersync_care_repository.dart';
import '../domain/care_policies.dart';
import '../domain/care_repository.dart';
import '../domain/cleaning_event.dart';
import '../domain/laundry_policy.dart';
import '../domain/rotation_policy.dart';
import '../../wear/domain/wear_event.dart';

final careRepositoryProvider = Provider<CareRepository?>((ref) {
  final user = ref.watch(currentUserProvider).value;
  final db = ref.watch(userDatabaseProvider).value;
  if (user == null || db == null) return null;
  return PowerSyncCareRepository(
    db: db,
    ownerId: user.id,
    clock: ref.watch(clockProvider),
  );
});

final carePoliciesProvider = StreamProvider<CarePolicies>((ref) {
  final repo = ref.watch(careRepositoryProvider);
  return repo?.watchPolicies() ?? const Stream.empty();
});

final _cleaningsProvider = StreamProvider<List<CleaningEvent>>((ref) {
  final repo = ref.watch(careRepositoryProvider);
  return repo?.watchCleanings() ?? const Stream.empty();
});

final _wearsProvider = StreamProvider<List<WearEvent>>((ref) {
  final repo = ref.watch(wearRepositoryProvider);
  return repo?.watchAll() ?? const Stream.empty();
});

final allGarmentsProvider = StreamProvider<List<Garment>>((ref) {
  final repo = ref.watch(wardrobeRepositoryProvider);
  return repo?.watchGarments(const GarmentFilter(includeArchived: true)) ??
      const Stream.empty();
});

/// Estado de lavagem de cada peça; `null` enquanto carrega.
final laundryStatesProvider = Provider<Map<GarmentId, LaundryState>?>((ref) {
  final garments = ref.watch(allGarmentsProvider).value;
  final wears = ref.watch(_wearsProvider).value;
  final cleanings = ref.watch(_cleaningsProvider).value;
  final policies = ref.watch(carePoliciesProvider).value;
  if (garments == null ||
      wears == null ||
      cleanings == null ||
      policies == null) {
    return null;
  }
  return LaundryPolicy.evaluate(
    garments: garments,
    wears: wears,
    cleanings: cleanings,
    policies: policies,
  );
});

/// Estado de rotação de cada peça, para hoje; `null` enquanto carrega.
final rotationStatesProvider = Provider<Map<GarmentId, RotationState>?>((ref) {
  final garments = ref.watch(allGarmentsProvider).value;
  final wears = ref.watch(_wearsProvider).value;
  final policies = ref.watch(carePoliciesProvider).value;
  if (garments == null || wears == null || policies == null) return null;
  return RotationPolicy.evaluate(
    garments: garments,
    wears: wears,
    policies: policies,
    today: todayFrom(ref.watch(clockProvider)),
  );
});

/// Última limpeza (para desfazer) de uma peça.
final lastCleaningProvider = Provider.family<CleaningEvent?, GarmentId>((
  ref,
  id,
) {
  final list = ref.watch(_cleaningsProvider).value ?? const [];
  CleaningEvent? last;
  for (final c in list) {
    if (c.garmentId == id) last = c; // ordenadas por data e registo
  }
  return last;
});
