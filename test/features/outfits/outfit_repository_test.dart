import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:guarda_roupa/features/account_sync/data/operation_upload_queue.dart';
import 'package:guarda_roupa/features/outfits/data/powersync_outfit_repository.dart';
import 'package:guarda_roupa/features/outfits/domain/outfit.dart';
import 'package:guarda_roupa/features/outfits/domain/outfit_repository.dart';
import 'package:guarda_roupa/features/wardrobe/data/powersync_wardrobe_repository.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment_attributes.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment_category.dart';
import 'package:powersync/powersync.dart';

import '../../support/test_database.dart';
import '../account_sync/data/operation_upload_queue_test.dart'
    show ScriptedUploader;
import '../wardrobe/domain/fakes.dart';
import '../wear/wear_repository_test.dart' show failureOf, ok;

Future<List<Map<String, Object?>>> outfitOperations(
  PowerSyncDatabase db,
) async {
  final batch = await db.getCrudBatch(limit: 1000);
  return [
    for (final e in batch?.crud ?? const <CrudEntry>[])
      if (e.table == 'outfit_operations') {'id': e.id, ...?e.opData},
  ];
}

Map<String, Object?> dataOf(Map<String, Object?> op) =>
    jsonDecode(op['data']! as String) as Map<String, Object?>;

void main() {
  group('papéis e regras', () {
    test('papel proposto pela categoria', () {
      expect(
        OutfitRole.suggestFor(GarmentCategory.tShirt, const []),
        OutfitRole.mainTop,
      );
      expect(
        OutfitRole.suggestFor(GarmentCategory.sweater, [OutfitRole.mainTop]),
        OutfitRole.midLayer,
        reason: 'segundo top é camada',
      );
      expect(
        OutfitRole.suggestFor(GarmentCategory.jeans, const []),
        OutfitRole.bottom,
      );
      expect(
        OutfitRole.suggestFor(GarmentCategory.coat, const []),
        OutfitRole.outerLayer,
      );
      expect(
        OutfitRole.suggestFor(GarmentCategory.sneakers, const []),
        OutfitRole.footwear,
      );
      expect(
        OutfitRole.suggestFor(GarmentCategory.boots, [OutfitRole.footwear]),
        OutfitRole.accessory,
        reason: 'um papel único ocupado não se repete',
      );
    });

    OutfitItem item(String id, OutfitRole role) =>
        OutfitItem(GarmentId(id), role);

    test('completo: top + baixo + calçado, ou peça única + calçado', () {
      expect(
        OutfitRules.missing([
          item('a', OutfitRole.mainTop),
          item('b', OutfitRole.bottom),
          item('c', OutfitRole.footwear),
        ]),
        isEmpty,
        reason: 't-shirt como top único, sem casaco',
      );
      expect(
        OutfitRules.missing([
          item('a', OutfitRole.onePiece),
          item('c', OutfitRole.footwear),
        ]),
        isEmpty,
      );
      expect(OutfitRules.missing([item('a', OutfitRole.mainTop)]), {
        OutfitRole.bottom,
        OutfitRole.footwear,
      });
    });

    test('validação', () {
      OutfitProblem? check(List<OutfitItem> items, {String? name}) =>
          OutfitRules.validate(OutfitDraft(items: items, name: name));
      expect(check(const []), OutfitProblem.noItems);
      expect(
        check([item('a', OutfitRole.mainTop), item('a', OutfitRole.midLayer)]),
        OutfitProblem.duplicateGarment,
      );
      expect(
        check([item('a', OutfitRole.footwear), item('b', OutfitRole.footwear)]),
        OutfitProblem.roleTaken,
      );
      expect(
        check([
          item('a', OutfitRole.accessory),
          item('b', OutfitRole.accessory),
        ]),
        isNull,
      );
      expect(
        check([item('a', OutfitRole.mainTop)], name: 'x' * 121),
        OutfitProblem.nameTooLong,
      );
      expect(
        check([for (var i = 0; i < 21; i++) item('g$i', OutfitRole.accessory)]),
        OutfitProblem.tooManyItems,
      );
    });
  });

  late PowerSyncDatabase db;
  late PowerSyncWardrobeRepository wardrobe;
  late PowerSyncOutfitRepository repo;

  setUp(() async {
    db = await openTestDatabase();
    wardrobe = PowerSyncWardrobeRepository(db: db, ownerId: 'user-a');
    repo = PowerSyncOutfitRepository(
      db: db,
      ownerId: 'user-a',
      clock: FixedClock(DateTime.utc(2026, 11, 3, 12)),
    );
  });

  Future<GarmentId> add(GarmentCategory c) async =>
      ok(await wardrobe.addGarment(GarmentDraft(category: c))).id;

  test('cria, aparece na lista e entra na fila', () async {
    final top = await add(GarmentCategory.tShirt);
    final jeans = await add(GarmentCategory.jeans);
    final shoes = await add(GarmentCategory.sneakers);

    final outfit = ok(
      await repo.createOutfit(
        OutfitDraft(
          name: '  Sexta ',
          occasions: const {Occasion.evening, Occasion.casual},
          items: [
            OutfitItem(top, OutfitRole.mainTop),
            OutfitItem(jeans, OutfitRole.bottom),
            OutfitItem(shoes, OutfitRole.footwear),
          ],
        ),
      ),
    );

    final listed = (await repo.watchOutfits().first).single;
    expect(listed.id, outfit.id);
    expect(listed.name, 'Sexta');
    expect(listed.occasions, {Occasion.casual, Occasion.evening});
    expect(listed.items.map((i) => i.role), [
      OutfitRole.mainTop,
      OutfitRole.bottom,
      OutfitRole.footwear,
    ]);
    final op = (await outfitOperations(db)).single;
    expect(op['kind'], 'create_outfit');
    expect(op['outfit_id'], outfit.id);
    expect(dataOf(op), {
      'items': [
        {'garment_id': top.value, 'role': 'main_top'},
        {'garment_id': jeans.value, 'role': 'bottom'},
        {'garment_id': shoes.value, 'role': 'footwear'},
      ],
      'name': 'Sexta',
      'occasions': ['casual', 'evening'],
    });
  });

  test('regras: inválidos, peças arquivadas e eliminadas', () async {
    final top = await add(GarmentCategory.tShirt);
    final old = await add(GarmentCategory.shirt);
    ok(await wardrobe.archiveGarment(old));
    final gone = await add(GarmentCategory.polo);
    ok(await wardrobe.deleteGarment(gone));

    expect(
      failureOf(await repo.createOutfit(const OutfitDraft(items: []))),
      isA<InvalidOutfit>(),
    );
    for (final id in [old, gone, GarmentId('nao-existe')]) {
      expect(
        failureOf(
          await repo.createOutfit(
            OutfitDraft(
              items: [
                OutfitItem(top, OutfitRole.mainTop),
                OutfitItem(id, OutfitRole.midLayer),
              ],
            ),
          ),
        ),
        isA<UnknownOutfitGarment>(),
      );
    }
    expect(await outfitOperations(db), isEmpty);
  });

  test('editar envia só o que mudou; arquivada que já estava fica', () async {
    final top = await add(GarmentCategory.tShirt);
    final jeans = await add(GarmentCategory.jeans);
    final shoes = await add(GarmentCategory.sneakers);
    final outfit = ok(
      await repo.createOutfit(
        OutfitDraft(
          name: 'A',
          items: [
            OutfitItem(top, OutfitRole.mainTop),
            OutfitItem(jeans, OutfitRole.bottom),
          ],
        ),
      ),
    );
    ok(await wardrobe.archiveGarment(jeans));

    final edited = ok(
      await repo.updateOutfit(
        outfit.id,
        outfit.toDraft().copyWithOccasions({Occasion.workCasual}),
      ),
    );
    expect(edited.occasions, {Occasion.workCasual});
    ok(
      await repo.updateOutfit(
        outfit.id,
        OutfitDraft(
          items: [...outfit.items, OutfitItem(shoes, OutfitRole.footwear)],
          occasions: const {Occasion.workCasual},
        ),
      ),
    );
    final unchanged = ok(
      await repo.updateOutfit(
        outfit.id,
        (await repo.watchOutfit(outfit.id).first)!.toDraft(),
      ),
    );
    expect(unchanged.items, hasLength(3));

    final ops = await outfitOperations(db);
    expect(ops.map((o) => o['kind']), [
      'create_outfit',
      'edit_outfit',
      'edit_outfit',
    ], reason: 'sem alterações não há operação');
    expect(dataOf(ops[1]), {
      'occasions': ['work_casual'],
    });
    expect(dataOf(ops[2]).keys, unorderedEquals(['name', 'items']));
    expect(dataOf(ops[2])['name'], isNull);
  });

  test('peça eliminada não apaga o conjunto', () async {
    final top = await add(GarmentCategory.tShirt);
    final jeans = await add(GarmentCategory.jeans);
    final outfit = ok(
      await repo.createOutfit(
        OutfitDraft(
          items: [
            OutfitItem(top, OutfitRole.mainTop),
            OutfitItem(jeans, OutfitRole.bottom),
          ],
        ),
      ),
    );
    ok(await wardrobe.deleteGarment(jeans));
    final still = (await repo.watchOutfit(outfit.id).first)!;
    expect(still.items.map((i) => i.garmentId), [top, jeans]);
  });

  test('eliminar: sai da lista; repetir é inofensivo', () async {
    final top = await add(GarmentCategory.tShirt);
    final outfit = ok(
      await repo.createOutfit(
        OutfitDraft(items: [OutfitItem(top, OutfitRole.mainTop)]),
      ),
    );
    ok(await repo.deleteOutfit(outfit.id));
    ok(await repo.deleteOutfit(outfit.id));
    expect(await repo.watchOutfits().first, isEmpty);
    expect(await repo.watchOutfit(outfit.id).first, isNull);
    expect(
      failureOf(await repo.updateOutfit(outfit.id, outfit.toDraft())),
      isA<OutfitNotFound>(),
    );
    expect((await outfitOperations(db)).map((o) => o['kind']), [
      'create_outfit',
      'delete_outfit',
    ]);
    expect(failureOf(await repo.deleteOutfit('nao')), isA<OutfitNotFound>());
  });

  test('a fila envia as operações de conjuntos depois das peças', () async {
    final top = await add(GarmentCategory.tShirt);
    ok(
      await repo.createOutfit(
        OutfitDraft(items: [OutfitItem(top, OutfitRole.mainTop)]),
      ),
    );
    final server = ScriptedUploader()
      ..responses.addAll([
        {'result': 'applied'},
        {'result': 'rejected', 'reason': 'not_found'},
      ]);
    await OperationUploadQueue(server).upload(db);
    expect(server.log, ['apply create', 'outfit create_outfit']);
    final outfitOp = server.received.last;
    expect(outfitOp['outfit_id'], isNotNull);
    expect((outfitOp['data']! as Map)['items'], isA<List<Object?>>());
    final conflict = await db.get('SELECT * FROM sync_conflicts');
    expect(conflict['kind'], 'create_outfit');
    expect(conflict['garment_id'], outfitOp['outfit_id']);
  });
}

extension on OutfitDraft {
  OutfitDraft copyWithOccasions(Set<Occasion> occasions) =>
      OutfitDraft(name: name, occasions: occasions, items: items);
}
