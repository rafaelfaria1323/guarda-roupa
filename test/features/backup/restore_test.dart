import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:guarda_roupa/core/domain/result.dart';
import 'package:guarda_roupa/features/account_sync/data/operation_upload_queue.dart';
import 'package:guarda_roupa/features/backup/data/backup_exporter.dart';
import 'package:guarda_roupa/features/backup/data/backup_restorer.dart';
import 'package:guarda_roupa/features/backup/domain/backup.dart';
import 'package:guarda_roupa/features/care/data/powersync_care_repository.dart';
import 'package:guarda_roupa/features/care/domain/care_policies.dart';
import 'package:guarda_roupa/features/outfits/data/powersync_outfit_repository.dart';
import 'package:guarda_roupa/features/outfits/domain/outfit.dart';
import 'package:guarda_roupa/features/wardrobe/data/powersync_wardrobe_repository.dart';
import 'package:guarda_roupa/features/wardrobe/domain/availability.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment_attributes.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment_category.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment_filter.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment_photo.dart';
import 'package:guarda_roupa/features/wear/data/powersync_wear_repository.dart';
import 'package:guarda_roupa/features/wear/domain/calendar_day.dart';
import 'package:powersync/powersync.dart';

import '../../support/test_database.dart';
import '../account_sync/data/operation_upload_queue_test.dart'
    show ScriptedUploader;
import '../wardrobe/domain/fakes.dart';
import 'backup_test.dart' show ok, photo;

F failureOf<T, F>(Result<T, F> r) => switch (r) {
  Ok() => fail('Esperava falha'),
  Err(:final failure) => failure,
};

void main() {
  late PowerSyncDatabase source;
  late PowerSyncWardrobeRepository sourceRepo;
  late PowerSyncDatabase target;
  late PowerSyncWardrobeRepository targetRepo;

  setUp(() async {
    source = await openTestDatabase();
    sourceRepo = PowerSyncWardrobeRepository(db: source, ownerId: 'user-a');
    target = await openTestDatabase();
    targetRepo = PowerSyncWardrobeRepository(db: target, ownerId: 'user-b');
  });

  BackupRestorer restorer({bool synced = true}) =>
      BackupRestorer(db: target, ownerId: 'user-b', accountSynced: synced);

  Future<Uint8List> backupOfSource() async =>
      ok(await BackupExporter(db: source).export());

  Future<List<Garment>> all(PowerSyncWardrobeRepository repo) =>
      repo.watchGarments(const GarmentFilter(includeArchived: true)).first;

  Future<void> fillSource() async {
    final a = ok(
      await sourceRepo.addGarment(
        const GarmentDraft(
          category: GarmentCategory.sweater,
          name: 'Grossa',
          attributes: GarmentAttributes(warmth: Warmth.warm, material: 'Lã'),
        ),
      ),
    );
    ok(await sourceRepo.addPhoto(a.id, photo(3)));
    ok(await sourceRepo.addPhoto(a.id, photo(4)));
    ok(await sourceRepo.setAvailability(a.id, Availability.washing));
    final b = ok(
      await sourceRepo.addGarment(
        const GarmentDraft(category: GarmentCategory.skirt, name: 'Velha'),
      ),
    );
    ok(await sourceRepo.archiveGarment(b.id));
  }

  test('recupera peças, estado, arquivo e fotos numa conta vazia', () async {
    await fillSource();
    final zip = await backupOfSource();

    final contents = ok(await restorer().inspect(zip));
    expect(contents.summary.garments, 2);
    expect(await all(targetRepo), isEmpty, reason: 'inspecionar não escreve');

    expect(ok(await restorer().apply(contents)), 2);

    final before = {for (final g in await all(sourceRepo)) g.name: g};
    final after = {for (final g in await all(targetRepo)) g.name: g};
    expect(after.keys, unorderedEquals(['Grossa', 'Velha']));
    final grossa = after['Grossa']!;
    expect(grossa.id, isNot(before['Grossa']!.id), reason: 'IDs novos');
    expect(grossa.attributes, before['Grossa']!.attributes);
    expect(grossa.availability, Availability.washing);
    expect(grossa.createdAt, before['Grossa']!.createdAt);
    expect(grossa.photos, hasLength(2));
    expect(grossa.photos.first.sha256, before['Grossa']!.photos.first.sha256);
    expect(
      grossa.photos.map((p) => p.id),
      isNot(contains(before['Grossa']!.photos.first.id)),
    );
    expect(
      await targetRepo.photoBytes(grossa.photos.first.id, PhotoVariant.main),
      photo(3).main,
    );
    expect(after['Velha']!.isArchived, isTrue);

    final kinds = [
      for (final op in await pendingOperations(target)) op['kind'],
    ];
    expect(kinds, [
      'create',
      'set_availability',
      'attach_photo',
      'attach_photo',
      'create',
      'archive',
    ]);
    final create = jsonDecode(
      (await pendingOperations(target)).first['data']! as String,
    ) as Map;
    expect(create['created_at'], isNotNull, reason: 'servidor mantém a data');
  });

  test('a fila envia os ficheiros antes de ligar as fotos', () async {
    await fillSource();
    ok(
      await restorer().apply(
        ok(await restorer().inspect(await backupOfSource())),
      ),
    );
    final server = ScriptedUploader();
    await OperationUploadQueue(server).upload(target);
    final firstAttach = server.log.indexOf('apply attach_photo');
    expect(
      server.log.sublist(0, firstAttach).where((l) => l.startsWith('upload')),
      hasLength(2),
    );
    expect(server.files, hasLength(4));
    expect(await target.getAll('SELECT * FROM sync_conflicts'), isEmpty);
  });

  test('conta com peças: recusa e não escreve nada', () async {
    await fillSource();
    final zip = await backupOfSource();
    ok(
      await targetRepo.addGarment(
        const GarmentDraft(category: GarmentCategory.shirt),
      ),
    );
    final r = await restorer().inspect(zip);
    expect(failureOf(r), isA<AccountNotEmpty>());
    expect(await all(targetRepo), hasLength(1));
  });

  test('conta vazia que fica com peças antes de confirmar: recusa', () async {
    await fillSource();
    final contents = ok(await restorer().inspect(await backupOfSource()));
    ok(
      await targetRepo.addGarment(
        const GarmentDraft(category: GarmentCategory.shirt),
      ),
    );
    final r = await restorer().apply(contents);
    expect(failureOf(r), isA<AccountNotEmpty>());
    expect(await all(targetRepo), hasLength(1));
    expect(await pendingOperations(target), hasLength(1));
  });

  test('antes da primeira sincronização não se sabe se está vazia', () async {
    final r = await restorer(synced: false).inspect(await backupOfSource());
    expect(failureOf(r), isA<AccountNotSyncedYet>());
  });

  test('ficheiro inválido: recusa sem tocar na conta', () async {
    final r = await restorer().inspect(Uint8List.fromList([1, 2, 3]));
    expect(failureOf(r), isA<InvalidBackupFile>());
    expect((failureOf(r) as InvalidBackupFile).problem, isA<NotABackup>());
    expect(await pendingOperations(target), isEmpty);
  });

  test('peças eliminadas na origem não voltam', () async {
    final g = ok(
      await sourceRepo.addGarment(
        const GarmentDraft(category: GarmentCategory.coat, name: 'Ida'),
      ),
    );
    ok(await sourceRepo.deleteGarment(g.id));
    final contents = ok(await restorer().inspect(await backupOfSource()));
    expect(contents.garments, isEmpty);
    expect(ok(await restorer().apply(contents)), 0);
    expect(await all(targetRepo), isEmpty);
  });

  test('recupera utilizações, limpezas e valores com os ids novos', () async {
    final clock = FixedClock(DateTime.utc(2026, 11, 3, 12));
    final wear = PowerSyncWearRepository(
      db: source,
      ownerId: 'user-a',
      clock: clock,
    );
    final care = PowerSyncCareRepository(
      db: source,
      ownerId: 'user-a',
      clock: clock,
    );
    final today = CalendarDay(2026, 11, 3);
    Future<GarmentId> add(GarmentCategory c, String name) async =>
        ok(await sourceRepo.addGarment(GarmentDraft(category: c, name: name)))
            .id;
    final top = await add(GarmentCategory.tShirt, 'Top');
    final jeans = await add(GarmentCategory.jeans, 'Ganga');
    final gone = await add(GarmentCategory.shirt, 'Ida');

    ok(await wear.recordWear(today.addDays(-2), {top, jeans}));
    ok(await wear.recordWear(today.addDays(-1), {top, gone}));
    final undone = ok(await wear.recordWear(today, {jeans}));
    ok(await wear.voidWear(undone.id));
    ok(await care.recordCleaning(top, today.addDays(-1)));
    ok(await care.setCategoryLaundry(GarmentCategory.tShirt, 2));
    ok(await care.setGarmentRotation(top, 5));
    ok(await care.setGarmentLaundry(gone, 1));
    ok(await sourceRepo.deleteGarment(gone));

    final contents = ok(await restorer().inspect(await backupOfSource()));
    expect(contents.summary.wears, 2, reason: 'desfeitas ficam de fora');
    expect(contents.summary.cleanings, 1);
    expect(contents.history.policies, hasLength(2));
    ok(await restorer().apply(contents));

    final ids = {for (final g in await all(targetRepo)) g.name: g.id.value};
    final wears = await target.getAll(
      'SELECT * FROM wear_events ORDER BY worn_on',
    );
    expect([for (final w in wears) w['worn_on']], ['2026-11-01', '2026-11-02']);
    expect(jsonDecode(wears[0]['garment_ids']! as String), [
      ids['Top'],
      ids['Ganga'],
    ]);
    expect(jsonDecode(wears[1]['garment_ids']! as String), [
      ids['Top'],
    ], reason: 'peça eliminada sai da utilização');
    final cleaning = await target.get('SELECT * FROM cleaning_events');
    expect(cleaning['garment_id'], ids['Top']);
    expect(cleaning['cleaned_on'], '2026-11-02');
    final policies = await target.getAll(
      'SELECT * FROM care_policies ORDER BY scope',
    );
    expect(
      [for (final p in policies) (p['scope'], p['target'])],
      [('category', 't_shirt'), ('garment', ids['Top'])],
    );
    expect(
      policies[1]['id'],
      PowerSyncCareRepository.policyId(
        'user-b',
        PolicyScope.garment,
        ids['Top']!,
      ),
    );

    final server = ScriptedUploader();
    await OperationUploadQueue(server).upload(target);
    expect(server.log.where((l) => l.startsWith('wear')), [
      'wear record_wear',
      'wear record_wear',
      'wear record_cleaning',
      'wear set_policy',
      'wear set_policy',
    ]);
    expect(
      server.log.indexOf('wear record_wear'),
      greaterThan(server.log.lastIndexOf('apply create')),
      reason: 'as peças chegam primeiro ao servidor',
    );
    expect(await target.getAll('SELECT * FROM sync_conflicts'), isEmpty);
  });

  test('recupera conjuntos com os ids novos das peças', () async {
    final outfits = PowerSyncOutfitRepository(db: source, ownerId: 'user-a');
    Future<GarmentId> add(GarmentCategory c, String name) async =>
        ok(await sourceRepo.addGarment(GarmentDraft(category: c, name: name)))
            .id;
    final top = await add(GarmentCategory.tShirt, 'Top');
    final shoes = await add(GarmentCategory.sneakers, 'Ténis');
    final old = await add(GarmentCategory.coat, 'Velho');
    ok(
      await outfits.createOutfit(
        OutfitDraft(
          name: 'Sexta',
          occasions: const {Occasion.workCasual},
          items: [
            OutfitItem(top, OutfitRole.mainTop),
            OutfitItem(shoes, OutfitRole.footwear),
            OutfitItem(old, OutfitRole.outerLayer),
          ],
        ),
      ),
    );
    ok(await sourceRepo.archiveGarment(old));

    final contents = ok(await restorer().inspect(await backupOfSource()));
    expect(contents.summary.outfits, 1);
    ok(await restorer().apply(contents));

    final ids = {for (final g in await all(targetRepo)) g.name: g.id};
    final restored = await PowerSyncOutfitRepository(
      db: target,
      ownerId: 'user-b',
    ).watchOutfits().first;
    final o = restored.single;
    expect(o.name, 'Sexta');
    expect(o.occasions, {Occasion.workCasual});
    expect(o.items, [
      OutfitItem(ids['Top']!, OutfitRole.mainTop),
      OutfitItem(ids['Ténis']!, OutfitRole.footwear),
      OutfitItem(ids['Velho']!, OutfitRole.outerLayer),
    ], reason: 'a peça arquivada continua no conjunto');

    final server = ScriptedUploader();
    await OperationUploadQueue(server).upload(target);
    expect(server.log.where((l) => l.startsWith('outfit')), [
      'outfit create_outfit',
    ]);
    expect(
      server.log.indexOf('outfit create_outfit'),
      greaterThan(server.log.lastIndexOf('apply archive')),
      reason: 'as peças chegam primeiro ao servidor',
    );
    final op = server.received.last;
    expect(op['outfit_id'], o.id);
    expect((op['data']! as Map)['items'], hasLength(3));
  });
}
