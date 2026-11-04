import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:guarda_roupa/features/account_sync/data/operation_upload_queue.dart';
import 'package:guarda_roupa/features/outfits/domain/outfit.dart';
import 'package:guarda_roupa/features/planner/data/powersync_plan_repository.dart';
import 'package:guarda_roupa/features/planner/domain/plan_entry.dart';
import 'package:guarda_roupa/features/planner/domain/plan_repository.dart';
import 'package:guarda_roupa/features/wardrobe/data/powersync_wardrobe_repository.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment_attributes.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment_category.dart';
import 'package:guarda_roupa/features/wear/domain/calendar_day.dart';
import 'package:powersync/powersync.dart';

import '../../support/test_database.dart';
import '../account_sync/data/operation_upload_queue_test.dart'
    show ScriptedUploader;
import '../wardrobe/domain/fakes.dart';
import '../wear/wear_repository_test.dart' show failureOf, ok;

Future<List<Map<String, Object?>>> planOperations(PowerSyncDatabase db) async {
  final batch = await db.getCrudBatch(limit: 1000);
  return [
    for (final e in batch?.crud ?? const <CrudEntry>[])
      if (e.table == 'plan_operations')
        {
          'id': e.id,
          ...?e.opData,
          'data': jsonDecode(e.opData!['data']! as String),
        },
  ];
}

void main() {
  // 9/11/2026 é segunda-feira.
  final monday = CalendarDay(2026, 11, 9);
  final saturday = CalendarDay(2026, 11, 14);

  group('regras da semana (P-19)', () {
    test('7 dias; úteis no trabalho, fim de semana a decidir', () {
      final week = WeekPlanRules.week(monday);
      expect(week, hasLength(7));
      expect(week.last, CalendarDay(2026, 11, 15));
      expect(week.where((d) => d.isWeekend), [
        saturday,
        CalendarDay(2026, 11, 15),
      ]);
      final weekday = PlanDraft.defaultFor(monday);
      expect(
        (weekday.occasion, weekday.tentative),
        (Occasion.workCasual, false),
      );
      final weekend = PlanDraft.defaultFor(saturday);
      expect((weekend.occasion, weekend.tentative), (null, true));
      expect(weekend.items, isEmpty);
    });

    test('estado do dia: confirmado só com utilização', () {
      final entry = PlanEntry(
        id: 'p',
        day: monday,
        items: const [],
        status: PlanStatus.accepted,
        version: 1,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );
      expect(entry.stateOn(monday, confirmed: false), PlanDayState.accepted);
      expect(entry.stateOn(monday, confirmed: true), PlanDayState.confirmed);
      expect(
        entry.stateOn(monday.addDays(1), confirmed: false),
        PlanDayState.unused,
      );
    });

    test('peças: como num conjunto, mas vazio é válido', () {
      OutfitItem item(String id, OutfitRole r) => OutfitItem(GarmentId(id), r);
      expect(WeekPlanRules.validate(const PlanDraft()), isNull);
      expect(
        WeekPlanRules.validate(
          PlanDraft(
            items: [
              item('a', OutfitRole.mainTop),
              item('b', OutfitRole.mainTop),
            ],
          ),
        ),
        PlanProblem.roleTaken,
      );
    });
  });

  late PowerSyncDatabase db;
  late PowerSyncWardrobeRepository wardrobe;
  late PowerSyncPlanRepository repo;

  setUp(() async {
    db = await openTestDatabase();
    wardrobe = PowerSyncWardrobeRepository(db: db, ownerId: 'user-a');
    repo = PowerSyncPlanRepository(
      db: db,
      ownerId: 'user-a',
      clock: FixedClock(DateTime.utc(2026, 11, 8, 12)),
    );
  });

  Future<GarmentId> add(GarmentCategory c) async =>
      ok(await wardrobe.addGarment(GarmentDraft(category: c))).id;

  test('criar um dia: entrada local e operação com o dia todo', () async {
    final top = await add(GarmentCategory.tShirt);
    final entry = ok(
      await repo.saveDay(
        monday,
        PlanDraft(
          occasion: Occasion.workCasual,
          items: [OutfitItem(top, OutfitRole.mainTop)],
        ),
      ),
    );
    expect(entry.version, 1);
    final week = await repo.watchDays(monday).first;
    expect(week.single.id, entry.id);
    expect(week.single.occasion, Occasion.workCasual);
    expect(week.single.items.single.garmentId, top);
    expect(week.single.tentative, isFalse);

    final op = (await planOperations(db)).single;
    expect(op['entry_id'], entry.id);
    expect(op['kind'], 'create_plan_entry');
    expect(op['data'], {
      'day': '2026-11-09',
      'occasion': 'work_casual',
      'tentative': false,
      'items': [
        {'garment_id': top.value, 'role': 'main_top'},
      ],
      'status': 'proposed',
    });
  });

  test('fim de semana provisório e vazio', () async {
    final entry = ok(
      await repo.saveDay(saturday, PlanDraft.defaultFor(saturday)),
    );
    final got = (await repo.watchDays(monday).first).single;
    expect(got.id, entry.id);
    expect((got.occasion, got.tentative), (null, true));
    expect(got.items, isEmpty);
  });

  test('editar envia só o que mudou, com a versão de base', () async {
    final top = await add(GarmentCategory.tShirt);
    final first = ok(await repo.saveDay(monday, PlanDraft.defaultFor(monday)));
    final same = ok(await repo.saveDay(monday, first.toDraft()));
    expect(same.version, 1, reason: 'nada mudou, nada se envia');

    final accepted = ok(
      await repo.saveDay(
        monday,
        PlanDraft(
          occasion: Occasion.workCasual,
          items: [OutfitItem(top, OutfitRole.mainTop)],
          status: PlanStatus.accepted,
        ),
      ),
    );
    expect(accepted.id, first.id);
    expect(accepted.version, 2);
    ok(
      await repo.saveDay(
        monday,
        PlanDraft(items: accepted.items, status: PlanStatus.accepted),
      ),
    );
    final ops = await planOperations(db);
    expect(ops.map((o) => o['kind']), [
      'create_plan_entry',
      'edit_plan_entry',
      'edit_plan_entry',
    ]);
    expect(ops[1]['data'], {
      'base_version': 1,
      'items': [
        {'garment_id': top.value, 'role': 'main_top'},
      ],
      'status': 'accepted',
    });
    expect(ops[2]['data'], {
      'base_version': 2,
      'occasion': null,
    }, reason: 'edições seguidas assentam umas nas outras');
  });

  test('peças desconhecidas, arquivadas ou repetidas são recusadas', () async {
    final top = await add(GarmentCategory.tShirt);
    expect(
      failureOf(
        await repo.saveDay(
          monday,
          const PlanDraft(
            items: [OutfitItem(GarmentId('nao'), OutfitRole.mainTop)],
          ),
        ),
      ),
      isA<UnknownPlanGarment>(),
    );
    expect(
      failureOf(
        await repo.saveDay(
          monday,
          PlanDraft(
            items: [
              OutfitItem(top, OutfitRole.mainTop),
              OutfitItem(top, OutfitRole.midLayer),
            ],
          ),
        ),
      ),
      isA<InvalidPlan>(),
    );
    ok(
      await repo.saveDay(
        monday,
        PlanDraft(items: [OutfitItem(top, OutfitRole.mainTop)]),
      ),
    );
    ok(await wardrobe.archiveGarment(top));
    // Já estava no plano: pode ficar.
    ok(
      await repo.saveDay(
        monday,
        PlanDraft(
          items: [OutfitItem(top, OutfitRole.mainTop)],
          status: PlanStatus.accepted,
        ),
      ),
    );
    expect(
      failureOf(
        await repo.saveDay(
          saturday,
          PlanDraft(items: [OutfitItem(top, OutfitRole.mainTop)]),
        ),
      ),
      isA<UnknownPlanGarment>(),
    );
  });

  test('proposta pendente vinda do servidor: aceitar e rejeitar', () async {
    final top = await add(GarmentCategory.tShirt);
    final entry = ok(await repo.saveDay(monday, PlanDraft.defaultFor(monday)));
    Future<void> propose(Map<String, Object?> proposal) => db.execute(
      'UPDATE plan_entries SET proposal = ? WHERE id = ?',
      [jsonEncode(proposal), entry.id],
    );
    await propose({
      'occasion': null,
      'items': [
        {'garment_id': top.value, 'role': 'main_top'},
      ],
    });
    final pending = (await repo.watchDays(monday).first).single.proposal!;
    expect(pending.changesOccasion, isTrue);
    expect(pending.occasion, isNull);
    expect(pending.items!.single.garmentId, top);
    expect(pending.tentative, isNull);

    ok(await repo.resolveProposal(entry.id, accept: true));
    final applied = (await repo.watchDays(monday).first).single;
    expect(applied.proposal, isNull);
    expect(applied.occasion, isNull);
    expect(applied.items.single.garmentId, top);

    await propose({'status': 'accepted'});
    ok(await repo.resolveProposal(entry.id, accept: false));
    final kept = (await repo.watchDays(monday).first).single;
    expect((kept.proposal, kept.status), (null, PlanStatus.proposed));

    ok(await repo.resolveProposal(entry.id, accept: false));
    expect(
      (await planOperations(db))
          .map((o) => (o['kind'], '${o['data']}'))
          .skip(1),
      [
        ('resolve_plan_proposal', '{accept: true}'),
        ('resolve_plan_proposal', '{accept: false}'),
      ],
      reason: 'sem proposta não se envia nada',
    );
    expect(
      failureOf(await repo.resolveProposal('nao', accept: true)),
      isA<PlanEntryNotFound>(),
    );
  });

  test('eliminar liberta o dia; repetir é inofensivo', () async {
    final entry = ok(await repo.saveDay(monday, PlanDraft.defaultFor(monday)));
    ok(await repo.deleteEntry(entry.id));
    ok(await repo.deleteEntry(entry.id));
    expect(await repo.watchDays(monday).first, isEmpty);
    final again = ok(await repo.saveDay(monday, const PlanDraft()));
    expect(again.id, isNot(entry.id));
    expect((await planOperations(db)).map((o) => o['kind']), [
      'create_plan_entry',
      'delete_plan_entry',
      'create_plan_entry',
    ]);
    expect(failureOf(await repo.deleteEntry('nao')), isA<PlanEntryNotFound>());
  });

  test('só os 7 dias pedidos', () async {
    ok(await repo.saveDay(monday.addDays(-1), const PlanDraft()));
    ok(await repo.saveDay(monday.addDays(6), const PlanDraft()));
    ok(await repo.saveDay(monday.addDays(7), const PlanDraft()));
    expect((await repo.watchDays(monday).first).map((e) => e.day), [
      monday.addDays(6),
    ]);
  });

  test('a fila envia ao plano; conflito fica registado', () async {
    ok(await repo.saveDay(monday, const PlanDraft()));
    final server = ScriptedUploader()
      ..responses.add({
        'result': 'conflict',
        'reason': 'day_taken',
        'entry_id': 'outra',
      });
    await OperationUploadQueue(server).upload(db);
    expect(server.log, ['plan create_plan_entry']);
    final op = server.received.single;
    expect(op['entry_id'], isNotNull);
    expect((op['data']! as Map)['day'], '2026-11-09');
    final conflict = await db.get('SELECT * FROM sync_conflicts');
    expect(conflict['result'], 'conflict');
    expect(conflict['reason'], 'day_taken');
    expect(conflict['garment_id'], op['entry_id']);
  });
}
