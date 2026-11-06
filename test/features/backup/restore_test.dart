import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:guarda_roupa/core/domain/result.dart';
import 'package:guarda_roupa/features/account_sync/data/operation_upload_queue.dart';
import 'package:guarda_roupa/features/backup/data/backup_exporter.dart';
import 'package:guarda_roupa/features/backup/data/backup_restorer.dart';
import 'package:guarda_roupa/features/backup/data/restore_plan.dart';
import 'package:guarda_roupa/features/backup/domain/backup.dart';
import 'package:guarda_roupa/features/care/data/powersync_care_repository.dart';
import 'package:guarda_roupa/features/care/domain/care_policies.dart';
import 'package:guarda_roupa/features/inspirations/data/powersync_inspiration_repository.dart';
import 'package:guarda_roupa/features/inspirations/data/powersync_preference_repository.dart';
import 'package:guarda_roupa/features/inspirations/domain/inspiration.dart';
import 'package:guarda_roupa/features/inspirations/domain/style_preference.dart';
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

import 'package:guarda_roupa/features/wardrobe/data/photo_files.dart';

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

    final preview = ok(await restorer().inspect(zip));
    expect(preview.contents.summary.garments, 2);
    expect(await all(targetRepo), isEmpty, reason: 'inspecionar não escreve');

    expect(
      ok(await restorer().apply(preview, restoreRemoved: true)).newGarments,
      hasLength(2),
    );

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
        restoreRemoved: true,
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

  test('conta com peças: junta só o que falta, sem mexer no resto', () async {
    await fillSource();
    final zip = await backupOfSource();
    final mine = ok(
      await targetRepo.addGarment(
        const GarmentDraft(category: GarmentCategory.shirt, name: 'Minha'),
      ),
    );
    final preview = ok(await restorer().inspect(zip));
    expect(preview.accountEmpty, isFalse);
    final plan = preview.plan(restoreRemoved: false);
    expect(plan.newGarments, hasLength(2));
    expect(plan.present, isEmpty);
    ok(await restorer().apply(preview, restoreRemoved: false));
    final names = {for (final g in await all(targetRepo)) g.name};
    expect(names, {'Minha', 'Grossa', 'Velha'});
    expect(
      (await all(targetRepo)).firstWhere((g) => g.id == mine.id).updatedAt,
      mine.updatedAt,
      reason: 'o que já lá estava fica como está',
    );
  });

  test('o mesmo backup outra vez não duplica nada', () async {
    final clock = FixedClock(DateTime.utc(2026, 11, 3, 12));
    final wear = PowerSyncWearRepository(
      db: source,
      ownerId: 'user-a',
      clock: clock,
    );
    await fillSource();
    final g = (await all(sourceRepo)).first;
    ok(await wear.recordWear(CalendarDay(2026, 11, 2), {g.id}));
    final zip = await backupOfSource();

    ok(
      await restorer().apply(
        ok(await restorer().inspect(zip)),
        restoreRemoved: true,
      ),
    );
    final again = ok(await restorer().inspect(zip));
    final plan = again.plan(restoreRemoved: true);
    expect(plan.nothingToAdd, isTrue);
    expect(plan.present, hasLength(2), reason: 'reconhecidas pela criação');
    ok(await restorer().apply(again, restoreRemoved: true));
    expect(await all(targetRepo), hasLength(2));
    expect(await target.getAll('SELECT * FROM wear_events'), hasLength(1));
  });

  test('na própria conta: apagadas só voltam se marcadas; o desfeito não '
      'volta', () async {
    final clock = FixedClock(DateTime.utc(2026, 11, 3, 12));
    final wear = PowerSyncWearRepository(
      db: source,
      ownerId: 'user-a',
      clock: clock,
    );
    final self = BackupRestorer(
      db: source,
      ownerId: 'user-a',
      accountSynced: true,
    );
    final keep = ok(
      await sourceRepo.addGarment(
        const GarmentDraft(category: GarmentCategory.jeans, name: 'Fica'),
      ),
    );
    final gone = ok(
      await sourceRepo.addGarment(
        const GarmentDraft(category: GarmentCategory.coat, name: 'Ida'),
      ),
    );
    final worn = ok(await wear.recordWear(CalendarDay(2026, 11, 2), {keep.id}));
    final zip = await backupOfSource();
    ok(await sourceRepo.deleteGarment(gone.id));
    ok(await wear.voidWear(worn.id));

    final preview = ok(await self.inspect(zip));
    final plan = preview.plan(restoreRemoved: false);
    expect(plan.present.keys, [keep.id]);
    expect(plan.removedGarments.map((g) => g.name), ['Ida']);
    expect(plan.newGarments, isEmpty);
    expect(plan.history.wears, isEmpty, reason: 'foi desfeita');
    expect(plan.nothingToAdd, isTrue);

    ok(await self.apply(preview, restoreRemoved: true));
    final names = [for (final g in await all(sourceRepo)) g.name]..sort();
    expect(names, ['Fica', 'Ida']);
    final back = (await all(sourceRepo)).firstWhere((g) => g.name == 'Ida');
    expect(back.id, isNot(gone.id), reason: 'id novo');
  });

  test('com cloud: o servidor diz o que foi apagado; sem rede, só para conta '
      'vazia', () async {
    await fillSource();
    final zip = await backupOfSource();
    final grossa = (await all(sourceRepo))
        .firstWhere((g) => g.name == 'Grossa');
    final asked = <RemovableTable>[];
    BackupRestorer cloud(RemoteRemovedLookup lookup) => BackupRestorer(
      db: target,
      ownerId: 'user-b',
      accountSynced: true,
      remoteRemoved: lookup,
    );
    Future<Set<String>> offline(RemovableTable t, List<String> ids) =>
        throw Exception('offline');

    expect(ok(await cloud(offline).inspect(zip)).accountEmpty, isTrue);

    ok(
      await targetRepo.addGarment(
        const GarmentDraft(category: GarmentCategory.shirt),
      ),
    );
    expect(failureOf(await cloud(offline).inspect(zip)), isA<NeedsNetwork>());

    final preview = ok(
      await cloud((t, ids) async {
        asked.add(t);
        return t == RemovableTable.garments ? {grossa.id.value} : {};
      }).inspect(zip),
    );
    expect(asked, contains(RemovableTable.garments));
    expect(
      preview.plan(restoreRemoved: false).removedGarments.map((g) => g.name),
      ['Grossa'],
    );
    expect(preview.plan(restoreRemoved: false).newGarments, hasLength(1));
    expect(preview.plan(restoreRemoved: true).newGarments, hasLength(2));
  });

  test('a conta muda entre o preview e confirmar: volta a comparar', () async {
    await fillSource();
    final preview = ok(await restorer().inspect(await backupOfSource()));
    ok(await restorer().apply(preview, restoreRemoved: true));
    final second = ok(await restorer().apply(preview, restoreRemoved: true));
    expect(second.newGarments, isEmpty);
    expect(await all(targetRepo), hasLength(2));
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
    final preview = ok(await restorer().inspect(await backupOfSource()));
    expect(preview.contents.garments, isEmpty);
    expect(
      ok(await restorer().apply(preview, restoreRemoved: true)).newGarments,
      isEmpty,
    );
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

    final preview = ok(await restorer().inspect(await backupOfSource()));
    expect(
      preview.contents.summary.wears,
      2,
      reason: 'desfeitas ficam de fora',
    );
    expect(preview.contents.summary.cleanings, 1);
    expect(preview.contents.history.policies, hasLength(2));
    ok(await restorer().apply(preview, restoreRemoved: true));

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

    final preview = ok(await restorer().inspect(await backupOfSource()));
    expect(preview.contents.summary.outfits, 1);
    ok(await restorer().apply(preview, restoreRemoved: true));

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

  test(
    'recupera inspirações e preferências sem repetir as que já existem',
    () async {
      final from = PowerSyncInspirationRepository(
        db: source,
        ownerId: 'user-a',
      );
      final fromPrefs = PowerSyncPreferenceRepository(
        db: source,
        ownerId: 'user-a',
      );
      ok(
        await sourceRepo.addGarment(
          const GarmentDraft(category: GarmentCategory.shirt),
        ),
      );
      final neutral = ok(
        await from.createInspiration(
          const InspirationDraft(
            title: 'Neutros',
            patterns: {GarmentPattern.plain},
          ),
        ),
      );
      ok(
        await from.createInspiration(
          const InspirationDraft(sourceUrl: 'https://example.com/x'),
        ),
      );
      ok(
        await fromPrefs.createPreferences(
          PreferenceDraft.fromInspiration(neutral),
        ),
      );
      ok(
        await fromPrefs.createPreference(
          const PreferenceDraft(
            subject: PreferenceSubject.combo,
            value: 'tonal',
            stance: PreferenceStance.avoid,
          ),
        ),
      );

      // O destino já tem uma inspiração igual e a mesma preferência, sem peças.
      final to = PowerSyncInspirationRepository(db: target, ownerId: 'user-b');
      final toPrefs = PowerSyncPreferenceRepository(
        db: target,
        ownerId: 'user-b',
      );
      final existing = ok(
        await to.createInspiration(
          const InspirationDraft(sourceUrl: 'https://example.com/x'),
        ),
      );
      ok(
        await toPrefs.createPreference(
          const PreferenceDraft(
            subject: PreferenceSubject.combo,
            value: 'tonal',
            stance: PreferenceStance.like,
          ),
        ),
      );

      final preview = ok(await restorer().inspect(await backupOfSource()));
      expect(preview.contents.summary.inspirations, 2);
      expect(preview.contents.summary.preferences, 2);
      ok(await restorer().apply(preview, restoreRemoved: true));

      final inspirations = await to.watchInspirations().first;
      expect(inspirations, hasLength(2));
      expect(inspirations.where((i) => i.id == existing.id), hasLength(1));
      final restored = inspirations.firstWhere((i) => i.title == 'Neutros');
      expect(restored.id, isNot(neutral.id));

      final prefs = await toPrefs.watchPreferences().first;
      expect(prefs, hasLength(2), reason: 'a combinação já existia');
      final plain = prefs.firstWhere(
        (p) => p.subject == PreferenceSubject.pattern,
      );
      expect(plain.inspirationId, restored.id, reason: 'origem com o id novo');
      expect(
        prefs.firstWhere((p) => p.subject == PreferenceSubject.combo).stance,
        PreferenceStance.like,
        reason: 'a do destino fica',
      );

      final server = ScriptedUploader();
      await OperationUploadQueue(server).upload(target);
      expect(server.log.where((l) => l.startsWith('style')), [
        'style create_inspiration',
        'style create_preference',
        'style create_inspiration',
        'style create_preference',
      ]);
    },
  );

  test('recupera a imagem da inspiração com id novo; os ficheiros sobem '
      'antes de ligar', () async {
    final from = PowerSyncInspirationRepository(db: source, ownerId: 'user-a');
    final i = ok(
      await from.createInspiration(
        const InspirationDraft(
          title: 'Camada comprida',
          proportions: {Proportion.longLayer},
        ),
      ),
    );
    final original = ok(await from.setImage(i.id, photo(9))).image!;

    final preview = ok(await restorer().inspect(await backupOfSource()));
    expect(preview.contents.summary.inspirationImages, 1);
    ok(await restorer().apply(preview, restoreRemoved: true));

    final to = PowerSyncInspirationRepository(db: target, ownerId: 'user-b');
    final restored = (await to.watchInspirations().first).single;
    expect(restored.proportions, {Proportion.longLayer});
    final image = restored.image!;
    expect(image.id, isNot(original.id));
    expect(image.sha256, original.sha256);
    expect(
      await PhotoFiles.get(target, image.id, PhotoVariant.main),
      photo(9).main,
    );

    final server = ScriptedUploader();
    await OperationUploadQueue(server).upload(target);
    expect(server.log, [
      'style create_inspiration',
      'upload ${image.id}/main',
      'upload ${image.id}/thumb',
      'style set_inspiration_image',
    ]);
  });
}
