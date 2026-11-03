import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:guarda_roupa/features/care/data/powersync_care_repository.dart';
import 'package:guarda_roupa/features/care/domain/care_policies.dart';
import 'package:guarda_roupa/features/care/domain/care_repository.dart';
import 'package:guarda_roupa/features/wardrobe/data/powersync_wardrobe_repository.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment_category.dart';
import 'package:guarda_roupa/features/wear/domain/calendar_day.dart';
import 'package:powersync/powersync.dart';

import '../../support/test_database.dart';
import '../wardrobe/domain/fakes.dart';
import '../wear/wear_repository_test.dart' show failureOf, ok, wearOperations;

void main() {
  late PowerSyncDatabase db;
  late PowerSyncWardrobeRepository wardrobe;
  late PowerSyncCareRepository repo;
  final today = CalendarDay(2026, 11, 3);

  setUp(() async {
    db = await openTestDatabase();
    wardrobe = PowerSyncWardrobeRepository(db: db, ownerId: 'user-a');
    repo = PowerSyncCareRepository(
      db: db,
      ownerId: 'user-a',
      clock: FixedClock(DateTime.utc(2026, 11, 3, 12)),
    );
  });

  Future<GarmentId> add() async => ok(
    await wardrobe.addGarment(
      const GarmentDraft(category: GarmentCategory.tShirt),
    ),
  ).id;

  Future<List<Map<String, Object?>>> ops() async => [
    for (final o in await wearOperations(db))
      {
        'kind': o['kind'],
        'event_id': o['event_id'],
        'data': jsonDecode(o['data']! as String),
      },
  ];

  test('id da política igual ao do servidor (md5 dono:âmbito:alvo)', () {
    // select md5('user-a:category:t_shirt')::uuid
    expect(
      PowerSyncCareRepository.policyId(
        'user-a',
        PolicyScope.category,
        't_shirt',
      ),
      '4cbc0157-8f29-7adb-5936-ee97fe134fe7',
    );
  });

  test('regista e desfaz limpezas; vão para a fila', () async {
    final g = await add();
    final c = ok(await repo.recordCleaning(g, today));
    expect((await repo.watchCleanings().first).single.garmentId, g);

    ok(await repo.voidCleaning(c.id));
    ok(await repo.voidCleaning(c.id));
    expect(await repo.watchCleanings().first, isEmpty);
    expect(await ops(), [
      {
        'kind': 'record_cleaning',
        'event_id': c.id,
        'data': {'garment_id': g.value, 'cleaned_on': '2026-11-03'},
      },
      {'kind': 'void_cleaning', 'event_id': c.id, 'data': <String, Object?>{}},
    ]);
  });

  test('limpeza: dia futuro e peça eliminada são rejeitados', () async {
    final g = await add();
    expect(
      (failureOf(
        await repo.recordCleaning(g, today.addDays(1)),
      ) as InvalidCare).problem,
      CareProblem.futureDay,
    );
    ok(await wardrobe.deleteGarment(g));
    expect(
      (failureOf(await repo.recordCleaning(g, today)) as InvalidCare).problem,
      CareProblem.unknownGarment,
    );
    expect(failureOf(await repo.voidCleaning('x')), isA<CleaningNotFound>());
    expect(await ops(), isEmpty);
  });

  test('políticas: campo a campo, null volta ao predefinido', () async {
    final g = await add();
    ok(await repo.setCategoryLaundry(GarmentCategory.jeans, 6));
    ok(await repo.setCategoryRotation(GarmentCategory.jeans, 2));
    ok(await repo.setGarmentLaundry(g, 0));

    var p = await repo.watchPolicies().first;
    expect(p.laundryByCategory, {GarmentCategory.jeans: 6});
    expect(p.rotationByCategory, {GarmentCategory.jeans: 2});
    expect(p.laundryByGarment, {g: 0});

    ok(await repo.setCategoryLaundry(GarmentCategory.jeans, null));
    p = await repo.watchPolicies().first;
    expect(p.laundryByCategory, isEmpty);
    expect(p.rotationByCategory, {GarmentCategory.jeans: 2});
    expect(
      await db.getAll('SELECT id FROM care_policies'),
      hasLength(2),
      reason: 'uma linha por âmbito e alvo',
    );

    final sent = await ops();
    expect(sent.first, {
      'kind': 'set_policy',
      'event_id': PowerSyncCareRepository.policyId(
        'user-a',
        PolicyScope.category,
        'jeans',
      ),
      'data': {'scope': 'category', 'target': 'jeans', 'laundry_after': 6},
    });
    expect(sent.last['data'], {
      'scope': 'category',
      'target': 'jeans',
      'laundry_after': null,
    });
  });

  test('políticas: fora dos limites e peça desconhecida', () async {
    expect(
      (failureOf(
        await repo.setCategoryLaundry(GarmentCategory.jeans, 31),
      ) as InvalidCare).problem,
      CareProblem.outOfRange,
    );
    expect(
      (failureOf(
        await repo.setGarmentLaundry(const GarmentId('x'), 1),
      ) as InvalidCare).problem,
      CareProblem.unknownGarment,
    );
    expect(await ops(), isEmpty);
  });
}
