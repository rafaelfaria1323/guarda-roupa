import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:guarda_roupa/core/domain/result.dart';
import 'package:guarda_roupa/features/wardrobe/data/powersync_wardrobe_repository.dart';
import 'package:guarda_roupa/features/wardrobe/domain/availability.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment_attributes.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment_category.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment_color.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment_filter.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment_photo.dart';
import 'package:guarda_roupa/features/wardrobe/domain/wardrobe_repository.dart';
import 'package:powersync/powersync.dart';

import '../../../support/test_database.dart';

T ok<T>(WardrobeResult<T> r) => switch (r) {
  Ok(:final value) => value,
  Err(:final failure) => fail('Esperava sucesso, obteve $failure'),
};

Map<String, Object?> dataOf(Map<String, Object?> op) =>
    jsonDecode(op['data']! as String) as Map<String, Object?>;

void main() {
  late PowerSyncDatabase db;
  late PowerSyncWardrobeRepository repo;

  setUp(() async {
    db = await openTestDatabase();
    repo = PowerSyncWardrobeRepository(db: db, ownerId: 'user-a');
  });

  test('adicionar guarda a peça e regista a operação create', () async {
    final g = ok(
      await repo.addGarment(
        GarmentDraft(
          category: GarmentCategory.tShirt,
          name: ' Branca ',
          colors: [GarmentColor.create(rgb: 0xFFFFFF, proportion: 0.9)!],
        ),
      ),
    );

    final stored = await repo.watchGarments(const GarmentFilter()).first;
    expect(stored.single.id, g.id);
    expect(stored.single.name, 'Branca');
    expect(stored.single.colors.single.rgb, 0xFFFFFF);

    final ops = await pendingOperations(db);
    expect(ops.single['kind'], 'create');
    expect(ops.single['garment_id'], g.id.value);
    expect(dataOf(ops.single), containsPair('category', 't_shirt'));
    expect(dataOf(ops.single), containsPair('name', 'Branca'));
  });

  test('dados inválidos não escrevem nada', () async {
    final r = await repo.addGarment(
      GarmentDraft(category: GarmentCategory.shirt, name: 'x' * 200),
    );
    expect(r, isA<Err<Garment, WardrobeFailure>>());
    expect(await repo.watchGarments(const GarmentFilter()).first, isEmpty);
    expect(await pendingOperations(db), isEmpty);
  });

  test('editar envia só os campos alterados, com from/to', () async {
    final g = ok(
      await repo.addGarment(
        const GarmentDraft(category: GarmentCategory.jeans, name: 'Azuis'),
      ),
    );
    ok(
      await repo.updateGarment(
        g.id,
        const GarmentDraft(
          category: GarmentCategory.jeans,
          name: 'Azuis escuras',
          brand: 'Marca',
        ),
      ),
    );

    final edit = (await pendingOperations(db)).last;
    expect(edit['kind'], 'edit');
    expect(dataOf(edit)['changes'], {
      'name': {'from': 'Azuis', 'to': 'Azuis escuras'},
      'brand': {'from': null, 'to': 'Marca'},
    });
  });

  test('editar sem alterações não cria operação', () async {
    final g = ok(
      await repo.addGarment(
        const GarmentDraft(category: GarmentCategory.coat, name: 'Casaco'),
      ),
    );
    ok(
      await repo.updateGarment(
        g.id,
        const GarmentDraft(category: GarmentCategory.coat, name: ' Casaco '),
      ),
    );
    expect(await pendingOperations(db), hasLength(1));
  });

  test('mudar disponibilidade regista o estado visto (from)', () async {
    final g = ok(
      await repo.addGarment(const GarmentDraft(category: GarmentCategory.polo)),
    );
    final dirty = ok(
      await repo.setAvailability(g.id, Availability.needsCleaning),
    );
    expect(dirty.isCandidate, isFalse);

    final op = (await pendingOperations(db)).last;
    expect(op['kind'], 'set_availability');
    expect(dataOf(op), {'from': 'available', 'to': 'needs_cleaning'});

    final available = await repo
        .watchGarments(
          const GarmentFilter(availability: {Availability.available}),
        )
        .first;
    expect(available, isEmpty);
  });

  test(
    'arquivar esconde por defeito e desarquivar envia a data vista',
    () async {
      final g = ok(
        await repo.addGarment(
          const GarmentDraft(category: GarmentCategory.boots),
        ),
      );
      final archived = ok(await repo.archiveGarment(g.id));
      expect(await repo.watchGarments(const GarmentFilter()).first, isEmpty);
      expect(
        await repo
            .watchGarments(const GarmentFilter(includeArchived: true))
            .first,
        hasLength(1),
      );

      ok(await repo.archiveGarment(g.id)); // idempotente: sem nova operação
      ok(await repo.unarchiveGarment(g.id));

      final ops = await pendingOperations(db);
      expect(ops.map((o) => o['kind']), ['create', 'archive', 'unarchive']);
      expect(
        DateTime.parse(dataOf(ops.last)['archived_at']! as String),
        archived.archivedAt,
      );
      // O arquivar envia o mesmo momento que o desarquivar usa como base:
      // o servidor guarda-o e o compare-and-set coincide mesmo offline.
      expect(dataOf(ops[1])['archived_at'], dataOf(ops.last)['archived_at']);
    },
  );

  test('duplicar cria peça nova com os mesmos dados', () async {
    final g = ok(
      await repo.addGarment(
        const GarmentDraft(category: GarmentCategory.tShirt, name: 'Preta'),
      ),
    );
    await repo.setAvailability(g.id, Availability.washing);
    final copy = ok(await repo.duplicateGarment(g.id));

    expect(copy.id, isNot(g.id));
    expect(copy.name, 'Preta');
    expect(copy.availability, Availability.available);
    expect(await repo.watchGarments(const GarmentFilter()).first, hasLength(2));
  });

  test('peça inexistente devolve GarmentNotFound', () async {
    final r = await repo.archiveGarment(const GarmentId('nao-existe'));
    expect(
      r,
      isA<Err<Garment, WardrobeFailure>>().having(
        (e) => e.failure,
        'failure',
        isA<GarmentNotFound>(),
      ),
    );
  });

  test('watchGarments emite de novo quando há alterações', () async {
    final stream = repo.watchGarments(const GarmentFilter());
    final seen = <int>[];
    final sub = stream.listen((list) => seen.add(list.length));
    await pumpEventQueue();
    await repo.addGarment(const GarmentDraft(category: GarmentCategory.skirt));
    await repo.addGarment(const GarmentDraft(category: GarmentCategory.dress));
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await sub.cancel();
    expect(seen.first, 0);
    expect(seen.last, 2);
  });

  test('linha com categoria desconhecida é ignorada, não inventada', () async {
    await db.execute(
      'INSERT INTO garments (id, category, availability, created_at) '
      "VALUES ('x', 'categoria_futura', 'available', '2026-11-03T00:00:00Z')",
    );
    expect(await repo.watchGarments(const GarmentFilter()).first, isEmpty);
  });

  test('eliminar tira a peça e regista delete com as fotos', () async {
    final g = ok(
      await repo.addGarment(const GarmentDraft(category: GarmentCategory.coat)),
    );
    final p = ok(
      await repo.addPhoto(
        g.id,
        ProcessedPhoto(
          width: 1,
          height: 1,
          main: Uint8List(1),
          thumb: Uint8List(1),
          sha256: '0' * 64,
        ),
      ),
    ).photos.single;

    ok(await repo.deleteGarment(g.id));

    expect(await repo.watchGarment(g.id).first, isNull);
    expect(
      await repo
          .watchGarments(const GarmentFilter(includeArchived: true))
          .first,
      isEmpty,
    );
    final op = (await pendingOperations(db)).last;
    expect(op['kind'], 'delete');
    expect(dataOf(op), {
      'photo_ids': [p.id],
    });
    expect(
      await repo.setAvailability(g.id, Availability.washing),
      isA<Err<Garment, WardrobeFailure>>(),
      reason: 'não se altera uma peça eliminada',
    );
  });

  group('fotografias', () {
    ProcessedPhoto photo(int seed) => ProcessedPhoto(
      width: 1600,
      height: 1200,
      main: Uint8List.fromList([1, 2, seed]),
      thumb: Uint8List.fromList([3, seed]),
      sha256: seed.toRadixString(16).padLeft(64, '0'),
    );

    Future<Garment> add() async => ok(
      await repo.addGarment(
        const GarmentDraft(category: GarmentCategory.shirt),
      ),
    );

    test('adicionar guarda os bytes, os metadados e a operação', () async {
      final g = await add();
      final after = ok(await repo.addPhoto(g.id, photo(7)));
      final p = after.photos.single;
      expect((p.width, p.height, p.bytes, p.thumbBytes), (1600, 1200, 3, 2));

      final stored = await repo.watchGarment(g.id).first;
      expect(stored!.photos.single, p);
      expect(await repo.photoBytes(p.id, PhotoVariant.main), [1, 2, 7]);
      expect(await repo.photoBytes(p.id, PhotoVariant.thumb), [3, 7]);

      final op = (await pendingOperations(db)).last;
      expect(op['kind'], 'attach_photo');
      expect(dataOf(op)['photo'], {
        'id': p.id,
        'width': 1600,
        'height': 1200,
        'bytes': 3,
        'thumb_bytes': 2,
        'sha256': p.sha256,
      });
    });

    test('no máximo 5 fotografias', () async {
      final g = await add();
      for (var i = 0; i < PhotoRules.maxPerGarment; i++) {
        ok(await repo.addPhoto(g.id, photo(i)));
      }
      final r = await repo.addPhoto(g.id, photo(9));
      expect(
        r,
        isA<Err<Garment, WardrobeFailure>>().having(
          (e) => e.failure,
          'failure',
          isA<TooManyPhotos>(),
        ),
      );
      expect((await repo.watchGarment(g.id).first)!.photos, hasLength(5));
    });

    test('remover regista detach e mantém os bytes até ao envio', () async {
      final g = await add();
      final p = ok(await repo.addPhoto(g.id, photo(1))).photos.single;
      final after = ok(await repo.removePhoto(g.id, p.id));
      expect(after.photos, isEmpty);
      expect((await repo.watchGarment(g.id).first)!.photos, isEmpty);
      expect(await repo.photoBytes(p.id, PhotoVariant.main), isNotNull);
      final op = (await pendingOperations(db)).last;
      expect(op['kind'], 'detach_photo');
      expect(dataOf(op), {'photo_id': p.id});

      final ops = (await pendingOperations(db)).length;
      ok(await repo.removePhoto(g.id, p.id));
      expect(
        await pendingOperations(db),
        hasLength(ops),
        reason: 'idempotente',
      );
    });

    test('editar, arquivar e duplicar mantêm as fotos certas', () async {
      final g = await add();
      ok(await repo.addPhoto(g.id, photo(1)));
      final edited = ok(
        await repo.updateGarment(
          g.id,
          const GarmentDraft(category: GarmentCategory.shirt, name: 'Nova'),
        ),
      );
      expect(edited.photos, hasLength(1));
      expect(ok(await repo.archiveGarment(g.id)).photos, hasLength(1));
      // A cópia é outra peça física: não partilha as fotografias.
      expect(ok(await repo.duplicateGarment(g.id)).photos, isEmpty);
    });
  });

  group('atributos', () {
    const full = GarmentAttributes(
      pattern: GarmentPattern.stripes,
      texture: SurfaceTexture.knit,
      warmth: Warmth.warm,
      rainOk: false,
      windOk: true,
      occasions: {Occasion.evening, Occasion.casual},
      material: ' 100% lã ',
      care: 'Lavar à mão',
    );

    test('guarda e lê todos os atributos, e envia-os no create', () async {
      final g = ok(
        await repo.addGarment(
          const GarmentDraft(
            category: GarmentCategory.sweater,
            attributes: full,
          ),
        ),
      );
      final stored = (await repo.watchGarment(g.id).first)!;
      expect(stored.attributes, full.copyWith(material: () => '100% lã'));

      final data = dataOf((await pendingOperations(db)).single);
      expect(data, containsPair('pattern', 'stripes'));
      expect(data, containsPair('rain_ok', false));
      expect(data, containsPair('wind_ok', true));
      expect(data, containsPair('occasions', ['casual', 'evening']));
      expect(data, containsPair('material', '100% lã'));
    });

    test('sem atributos fica tudo desconhecido', () async {
      final g = ok(
        await repo.addGarment(
          const GarmentDraft(category: GarmentCategory.sweater),
        ),
      );
      expect((await repo.watchGarment(g.id).first)!.attributes.isEmpty, isTrue);
      final data = dataOf((await pendingOperations(db)).single);
      expect(data, containsPair('rain_ok', null));
      expect(data, containsPair('occasions', <Object?>[]));
    });

    test('editar envia uma alteração por atributo', () async {
      final g = ok(
        await repo.addGarment(
          const GarmentDraft(
            category: GarmentCategory.sweater,
            attributes: full,
          ),
        ),
      );
      ok(
        await repo.updateGarment(
          g.id,
          GarmentDraft(
            category: GarmentCategory.sweater,
            attributes: g.attributes.copyWith(
              pattern: () => null,
              rainOk: () => true,
              occasions: {Occasion.casual},
            ),
          ),
        ),
      );
      final edit = (await pendingOperations(db)).last;
      expect(dataOf(edit)['changes'], {
        'pattern': {'from': 'stripes', 'to': null},
        'rain_ok': {'from': false, 'to': true},
        'occasions': {
          'from': ['casual', 'evening'],
          'to': ['casual'],
        },
      });
      final stored = (await repo.watchGarment(g.id).first)!;
      expect(stored.attributes.pattern, isNull);
      expect(stored.attributes.rainOk, isTrue);
      expect(stored.attributes.occasions, {Occasion.casual});
    });

    test('valores desconhecidos (versão futura) ficam por saber', () async {
      await db.execute(
        'INSERT INTO garments (id, category, availability, created_at, '
        'pattern, warmth, rain_ok, occasions) VALUES '
        "('x', 'sweater', 'available', '2026-11-03T00:00:00Z', "
        "'padrao_futuro', 'warm', 1, '[\"futura\", \"evening\"]')",
      );
      final g = (await repo.watchGarments(const GarmentFilter()).first).single;
      expect(g.attributes.pattern, isNull);
      expect(g.attributes.warmth, Warmth.warm);
      expect(g.attributes.rainOk, isTrue);
      expect(g.attributes.occasions, {Occasion.evening});
    });

    test('material demasiado longo não guarda', () async {
      final r = await repo.addGarment(
        GarmentDraft(
          category: GarmentCategory.sweater,
          attributes: GarmentAttributes(material: 'x' * 121),
        ),
      );
      expect(r, isA<Err<Garment, WardrobeFailure>>());
    });

    test('filtro por ocasião', () async {
      ok(
        await repo.addGarment(
          const GarmentDraft(
            category: GarmentCategory.shirt,
            name: 'Noite',
            attributes: GarmentAttributes(occasions: {Occasion.evening}),
          ),
        ),
      );
      ok(
        await repo.addGarment(
          const GarmentDraft(category: GarmentCategory.shirt, name: 'Sem'),
        ),
      );
      final found = await repo
          .watchGarments(const GarmentFilter(occasions: {Occasion.evening}))
          .first;
      expect(found.map((g) => g.name), ['Noite']);
    });
  });
}
