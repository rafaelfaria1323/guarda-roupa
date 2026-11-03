import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:guarda_roupa/core/domain/result.dart';
import 'package:guarda_roupa/features/wardrobe/data/powersync_wardrobe_repository.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment_category.dart';
import 'package:guarda_roupa/features/wear/data/powersync_wear_repository.dart';
import 'package:guarda_roupa/features/wear/domain/calendar_day.dart';
import 'package:guarda_roupa/features/wear/domain/wear_repository.dart';
import 'package:powersync/powersync.dart';

import '../../support/test_database.dart';
import '../wardrobe/domain/fakes.dart';

T ok<T, F>(Result<T, F> r) => switch (r) {
  Ok(:final value) => value,
  Err(:final failure) => fail('Esperava sucesso, obteve $failure'),
};

F failureOf<T, F>(Result<T, F> r) => switch (r) {
  Ok(:final value) => fail('Esperava falha, obteve $value'),
  Err(:final failure) => failure,
};

Future<List<Map<String, Object?>>> wearOperations(PowerSyncDatabase db) async {
  final batch = await db.getCrudBatch(limit: 1000);
  return [
    for (final e in batch?.crud ?? const <CrudEntry>[])
      if (e.table == 'wear_operations') {'id': e.id, ...?e.opData},
  ];
}

void main() {
  group('CalendarDay', () {
    test('conta dias de calendário, também na mudança de hora', () {
      final d = CalendarDay(2026, 10, 24);
      expect(d.addDays(1).iso, '2026-10-25');
      expect(d.daysUntil(CalendarDay(2026, 10, 27)), 3);
      expect(CalendarDay(2026, 3, 28).addDays(3).iso, '2026-03-31');
      expect(CalendarDay(2026, 12, 31).addDays(1).iso, '2027-01-01');
    });

    test('lê só datas válidas', () {
      expect(CalendarDay.tryParse('2026-11-03'), CalendarDay(2026, 11, 3));
      expect(CalendarDay.tryParse('2026-02-30'), isNull);
      expect(CalendarDay.tryParse('3/11/2026'), isNull);
      expect(CalendarDay.tryParse(null), isNull);
    });
  });

  late PowerSyncDatabase db;
  late PowerSyncWardrobeRepository wardrobe;
  late PowerSyncWearRepository repo;
  late FixedClock clock;
  final today = CalendarDay(2026, 11, 3);

  setUp(() async {
    db = await openTestDatabase();
    wardrobe = PowerSyncWardrobeRepository(db: db, ownerId: 'user-a');
    // Meio-dia UTC: o mesmo dia em qualquer fuso europeu.
    clock = FixedClock(DateTime.utc(2026, 11, 3, 12));
    repo = PowerSyncWearRepository(db: db, ownerId: 'user-a', clock: clock);
  });

  Future<GarmentId> add(GarmentCategory c) async =>
      ok(await wardrobe.addGarment(GarmentDraft(category: c))).id;

  test('regista, aparece no dia e no histórico, e entra na fila', () async {
    final top = await add(GarmentCategory.tShirt);
    final jeans = await add(GarmentCategory.jeans);

    final event = ok(await repo.recordWear(today, {top, jeans}));

    final day = await repo.watchDay(today).first;
    expect(day.single.id, event.id);
    expect(day.single.garmentIds, [top, jeans]);
    expect((await repo.watchGarmentHistory(top).first).single.id, event.id);
    expect(await repo.watchGarmentHistory(GarmentId('outra')).first, isEmpty);

    final ops = await wearOperations(db);
    expect(ops.single['kind'], 'record_wear');
    expect(ops.single['event_id'], event.id);
    expect(jsonDecode(ops.single['data']! as String), {
      'worn_on': '2026-11-03',
      'garment_ids': [top.value, jeans.value],
    });
  });

  test('a entrada do plano segue com a operação', () async {
    final top = await add(GarmentCategory.tShirt);
    ok(await repo.recordWear(today, {top}, planEntryId: 'plano-1'));
    final data = jsonDecode(
      (await wearOperations(db)).single['data']! as String,
    ) as Map<String, Object?>;
    expect(data['plan_entry_id'], 'plano-1');
  });

  test('regras: peças, máximo, futuro e peças eliminadas', () async {
    final top = await add(GarmentCategory.tShirt);
    final gone = await add(GarmentCategory.shirt);
    ok(await wardrobe.deleteGarment(gone));

    InvalidWear invalid(WearResult<Object?> r) => failureOf(r) as InvalidWear;
    expect(
      invalid(await repo.recordWear(today, {})).problem,
      WearProblem.noGarments,
    );
    expect(
      invalid(await repo.recordWear(today.addDays(1), {top})).problem,
      WearProblem.futureDay,
      reason: 'planear não é usar',
    );
    expect(
      invalid(await repo.recordWear(today, {top, gone})).problem,
      WearProblem.unknownGarment,
    );
    expect(
      invalid(
        await repo.recordWear(today, {
          for (var i = 0; i < 31; i++) GarmentId('g$i'),
        }),
      ).problem,
      WearProblem.tooManyGarments,
    );
    expect(await wearOperations(db), isEmpty);

    ok(await repo.recordWear(today.addDays(-5), {top}));
  });

  test('peças arquivadas podem ser registadas (registo tardio)', () async {
    final top = await add(GarmentCategory.tShirt);
    ok(await wardrobe.archiveGarment(top));
    ok(await repo.recordWear(today.addDays(-1), {top}));
  });

  test('desfazer tira do dia e do histórico; repetir é inofensivo', () async {
    final top = await add(GarmentCategory.tShirt);
    final event = ok(await repo.recordWear(today, {top}));

    ok(await repo.voidWear(event.id));
    ok(await repo.voidWear(event.id));

    expect(await repo.watchDay(today).first, isEmpty);
    expect(await repo.watchGarmentHistory(top).first, isEmpty);
    expect(await repo.watchEvent(event.id).first, isNull);
    expect((await wearOperations(db)).map((o) => o['kind']), [
      'record_wear',
      'void_wear',
    ]);
    expect(failureOf(await repo.voidWear('nao-existe')), isA<WearNotFound>());
  });

  test(
    'corrigir = desfazer + registar, mesmo dia e entrada de plano',
    () async {
      final top = await add(GarmentCategory.tShirt);
      final other = await add(GarmentCategory.polo);
      final first = ok(
        await repo.recordWear(today.addDays(-1), {top}, planEntryId: 'p'),
      );

      final fixed = ok(await repo.correctWear(first.id, {other}));

      expect(fixed.id, isNot(first.id));
      expect(fixed.wornOn, today.addDays(-1));
      expect(fixed.planEntryId, 'p');
      expect(await repo.watchGarmentHistory(top).first, isEmpty);
      expect((await repo.watchGarmentHistory(other).first).single.id, fixed.id);
      final ops = await wearOperations(db);
      expect(ops.map((o) => o['kind']), [
        'record_wear',
        'void_wear',
        'record_wear',
      ]);
    },
  );

  test('corrigir com peças inválidas não desfaz nada', () async {
    final top = await add(GarmentCategory.tShirt);
    final event = ok(await repo.recordWear(today, {top}));
    expect(failureOf(await repo.correctWear(event.id, {})), isA<InvalidWear>());
    expect((await repo.watchDay(today).first).single.id, event.id);
    expect(await wearOperations(db), hasLength(1));
  });

  test('histórico da mais recente para a mais antiga', () async {
    final top = await add(GarmentCategory.tShirt);
    ok(await repo.recordWear(today.addDays(-3), {top}));
    ok(await repo.recordWear(today, {top}));
    ok(await repo.recordWear(today.addDays(-1), {top}));
    final days = (await repo.watchGarmentHistory(top).first).map(
      (e) => e.wornOn.iso,
    );
    expect(days, ['2026-11-03', '2026-11-02', '2026-10-31']);
  });
}
