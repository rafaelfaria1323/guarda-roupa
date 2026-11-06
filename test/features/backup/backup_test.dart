import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guarda_roupa/core/domain/result.dart';
import 'package:guarda_roupa/features/backup/data/backup_codec.dart';
import 'package:guarda_roupa/features/backup/data/backup_exporter.dart';
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
import 'package:guarda_roupa/features/wardrobe/domain/garment.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment_attributes.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment_category.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment_color.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment_photo.dart';
import 'package:guarda_roupa/features/wardrobe/domain/reference_color.dart';
import 'package:guarda_roupa/features/wear/data/powersync_wear_repository.dart';
import 'package:guarda_roupa/features/wear/domain/calendar_day.dart';
import 'package:powersync/powersync.dart';

import '../../support/test_database.dart';
import '../wardrobe/domain/fakes.dart';

T ok<T, F>(Result<T, F> r) => switch (r) {
  Ok(:final value) => value,
  Err(:final failure) => fail('Esperava sucesso, obteve $failure'),
};

ProcessedPhoto photo(int seed) {
  final main = Uint8List.fromList(List.generate(50, (i) => (i * seed) % 256));
  return ProcessedPhoto(
    width: 10,
    height: 8,
    main: main,
    thumb: Uint8List.fromList([seed, seed]),
    sha256: sha256.convert(main).toString(),
  );
}

/// Reescreve um ZIP aplicando [edit] a cada ficheiro (nome → bytes).
Uint8List rewrite(
  Uint8List zip,
  Map<String, Uint8List>? Function(String name, Uint8List bytes) edit,
) {
  final out = Archive();
  for (final f in ZipDecoder().decodeBytes(zip)) {
    final replaced = edit(f.name, f.content) ?? {f.name: f.content};
    for (final MapEntry(:key, :value) in replaced.entries) {
      out.add(ArchiveFile.bytes(key, value));
    }
  }
  return ZipEncoder().encodeBytes(out);
}

Map<String, Object?> manifestOf(Uint8List zip) => jsonDecode(
  utf8.decode(ZipDecoder().decodeBytes(zip).findFile('manifest.json')!.content),
) as Map<String, Object?>;

Uint8List withManifest(
  Uint8List zip,
  void Function(Map<String, Object?> m) edit,
) {
  final m = manifestOf(zip);
  edit(m);
  return rewrite(
    zip,
    (name, bytes) =>
        name == 'manifest.json' ? {name: utf8.encode(jsonEncode(m))} : null,
  );
}

/// Troca o conteúdo de um ficheiro JSON e acerta o manifest (hash certo,
/// conteúdo possivelmente inválido).
Uint8List withJson(Uint8List zip, String path, Object? json) {
  final data = utf8.encode(jsonEncode(json));
  final bad = rewrite(zip, (name, bytes) => name == path ? {name: data} : null);
  return withManifest(bad, (m) {
    for (final f in (m['files']! as List).cast<Map<String, Object?>>()) {
      if (f['path'] == path) {
        f['size'] = data.length;
        f['sha256'] = sha256.convert(data).toString();
      }
    }
  });
}

/// Tira [paths] do ZIP e do manifest e marca-o com [version].
Uint8List downgrade(Uint8List zip, int version, List<String> paths) =>
    withManifest(rewrite(zip, (name, _) => paths.contains(name) ? {} : null), (
      m,
    ) {
      m['version'] = version;
      (m['files']! as List).removeWhere(
        (f) => paths.contains((f as Map)['path']),
      );
    });

Map<String, Object?> jsonIn(Uint8List zip, String path) => jsonDecode(
  utf8.decode(ZipDecoder().decodeBytes(zip).findFile(path)!.content),
) as Map<String, Object?>;

void main() {
  late PowerSyncDatabase db;
  late PowerSyncWardrobeRepository repo;

  setUp(() async {
    db = await openTestDatabase();
    repo = PowerSyncWardrobeRepository(db: db, ownerId: 'user-a');
  });

  Future<Garment> add(GarmentDraft draft, {int photos = 0}) async {
    var g = ok(await repo.addGarment(draft));
    for (var i = 0; i < photos; i++) {
      g = ok(await repo.addPhoto(g.id, photo(i + 3)));
    }
    return g;
  }

  Future<Uint8List> export({RemotePhoto? remote}) async =>
      ok(await BackupExporter(db: db, remote: remote).export());

  group('exportar e ler', () {
    test('ida e volta: peças, atributos e fotos intactos', () async {
      final a = await add(
        GarmentDraft(
          category: GarmentCategory.sweater,
          name: 'Grossa',
          colors: [GarmentColor.create(rgb: 0x1F2A44, proportion: 0.7)!],
          attributes: const GarmentAttributes(
            warmth: Warmth.warm,
            rainOk: false,
            formality: Formality.relaxed,
            occasions: {Occasion.evening},
            material: 'Lã',
          ),
        ),
        photos: 2,
      );
      final b = await add(const GarmentDraft(category: GarmentCategory.skirt));
      ok(await repo.archiveGarment(b.id));
      final deleted = await add(
        const GarmentDraft(category: GarmentCategory.coat),
      );
      ok(await repo.deleteGarment(deleted.id));

      final zip = await export();
      final contents = ok(BackupCodec.decode(zip));

      expect(contents.summary.garments, 2, reason: 'eliminadas ficam fora');
      expect(contents.summary.photos, 2);
      expect(contents.summary.pendingOperations, greaterThan(0));
      final restored = {for (final g in contents.garments) g.id: g};
      final current = (await repo.watchGarment(a.id).first)!;
      expect(restored[a.id]!.name, 'Grossa');
      expect(restored[a.id]!.attributes, current.attributes);
      expect(restored[a.id]!.colors.single.rgb, 0x1F2A44);
      expect(restored[a.id]!.photos, current.photos);
      expect(restored[b.id]!.isArchived, isTrue);
      final first = current.photos.first;
      expect(contents.photoFiles[(first.id, PhotoVariant.main)], photo(3).main);
    });

    test('manifest com versão, contagens e hashes; sem segredos', () async {
      await add(const GarmentDraft(category: GarmentCategory.shirt), photos: 1);
      final m = manifestOf(await export());
      expect(m['format'], 'guarda-roupa-backup');
      expect(m['version'], BackupFormat.version);
      expect(m['counts'], {
        'garments': 1,
        'photos': 2,
        'wear_events': 0,
        'cleaning_events': 0,
        'care_policies': 0,
        'outfits': 0,
        'inspirations': 0,
        'style_preferences': 0,
      });
      final files = (m['files']! as List).cast<Map<String, Object?>>();
      expect(
        files.map((f) => f['path']),
        containsAll([
          'data/garments.json',
          'data/history.json',
          'data/outfits.json',
          'data/style.json',
        ]),
      );
      expect(files.every((f) => (f['sha256']! as String).length == 64), true);
      final text = jsonEncode(m);
      expect(text, isNot(contains('owner_id')));
      expect(text, isNot(contains('token')));
    });

    test('guarda-roupa vazio também exporta', () async {
      final contents = ok(BackupCodec.decode(await export()));
      expect(contents.garments, isEmpty);
    });
  });

  group('fotos que não estão neste dispositivo', () {
    Future<Garment> withRemoteOnlyPhoto() async {
      final g = await add(
        const GarmentDraft(category: GarmentCategory.shirt),
        photos: 1,
      );
      await db.execute('DELETE FROM photo_files');
      return g;
    }

    test('descarrega da cloud', () async {
      final g = await withRemoteOnlyPhoto();
      final asked = <String>[];
      final zip = await export(
        remote: (p, v) async {
          asked.add('${p.id}/${v.id}');
          return photo(3).bytesOf(v);
        },
      );
      expect(asked, hasLength(2));
      expect(ok(BackupCodec.decode(zip)).summary.photos, 1);
      expect(g.photos, hasLength(1));
    });

    test('sem rede: falha explícita, sem ficheiro incompleto', () async {
      await withRemoteOnlyPhoto();
      final r = await BackupExporter(
        db: db,
        remote: (_, _) async => throw Exception('sem rede'),
      ).export();
      final failure = (r as Err<Uint8List, BackupProblem>).failure;
      expect(failure, isA<MissingPhotos>());
      expect((failure as MissingPhotos).count, 2);
    });

    test('descarregada mas diferente (hash) conta como em falta', () async {
      await withRemoteOnlyPhoto();
      final r = await BackupExporter(
        db: db,
        remote: (_, v) async => Uint8List.fromList([9, 9, 9]),
      ).export();
      expect((r as Err).failure, isA<MissingPhotos>());
    });
  });

  group('ficheiros inválidos são rejeitados por inteiro', () {
    late Uint8List zip;
    setUp(() async {
      await add(const GarmentDraft(category: GarmentCategory.shirt), photos: 1);
      zip = await export();
    });

    BackupProblem problem(Uint8List bytes) => (BackupCodec.decode(
      bytes,
    ) as Err<BackupContents, BackupProblem>).failure;

    test('não é ZIP', () {
      expect(
        problem(Uint8List.fromList(utf8.encode('olá'))),
        isA<NotABackup>(),
      );
    });

    test('ZIP de outra coisa', () {
      final other = ZipEncoder().encodeBytes(
        Archive()..add(ArchiveFile.string('a.txt', 'x')),
      );
      expect(problem(other), isA<NotABackup>());
    });

    test('versão mais recente', () {
      final next = BackupFormat.version + 1;
      final p = problem(withManifest(zip, (m) => m['version'] = next));
      expect(p, isA<UnsupportedBackupVersion>());
      expect((p as UnsupportedBackupVersion).version, next);
    });

    test('foto alterada', () {
      final bad = rewrite(
        zip,
        (name, bytes) => name.endsWith('main.jpg')
            ? {
                name: Uint8List.fromList([...bytes]..[0] ^= 1),
              }
            : null,
      );
      expect(problem(bad), isA<CorruptBackup>());
    });

    test('foto em falta', () {
      final bad = rewrite(
        zip,
        (name, bytes) => name.endsWith('thumb.jpg') ? {} : null,
      );
      expect(problem(bad), isA<CorruptBackup>());
    });

    test('caminho fora da pasta (..)', () {
      final bad = withManifest(zip, (m) {
        (m['files']! as List).add({
          'path': '../fora.json',
          'size': 1,
          'sha256': '0' * 64,
        });
      });
      expect(problem(bad), isA<CorruptBackup>());
    });

    test('ficheiro extra que o manifest não declara', () {
      final bad = rewrite(
        zip,
        (name, bytes) => name == 'manifest.json'
            ? {name: bytes, 'photos/x/main.jpg': Uint8List(1)}
            : null,
      );
      expect(problem(bad), isA<CorruptBackup>());
    });

    test('peça inválida (hash certo, conteúdo sem categoria)', () {
      final bad = withJson(zip, 'data/garments.json', {
        'garments': [
          {'id': 'abc', 'availability': 'available'},
        ],
      });
      expect(problem(bad), isA<CorruptBackup>());
    });

    test('v2 sem histórico', () {
      final bad = withManifest(
        rewrite(zip, (name, _) => name == 'data/history.json' ? {} : null),
        (m) => (m['files']! as List).removeWhere(
          (f) => (f as Map)['path'] == 'data/history.json',
        ),
      );
      expect(problem(bad), isA<CorruptBackup>());
    });

    test('v3 sem conjuntos', () {
      final bad = withManifest(
        rewrite(zip, (name, _) => name == 'data/outfits.json' ? {} : null),
        (m) => (m['files']! as List).removeWhere(
          (f) => (f as Map)['path'] == 'data/outfits.json',
        ),
      );
      expect(problem(bad), isA<CorruptBackup>());
    });

    test('v4 sem estilo', () {
      expect(
        problem(downgrade(zip, 4, ['data/style.json'])),
        isA<CorruptBackup>(),
      );
    });

    test('inspiração ou preferência inválida', () {
      Map<String, Object?> inspiration([
        Map<String, Object?> extra = const {},
      ]) => {
        'id': 'i1',
        'title': 'Neutros',
        'source_url': 'https://example.com/a',
        'notes': null,
        'palette': [0x1F2A44],
        'formality': 'dressy',
        'patterns': ['stripes'],
        'textures': <String>[],
        'occasions': ['evening'],
        'created_at': '2026-11-01T10:00:00.000Z',
        'updated_at': '2026-11-01T10:00:00.000Z',
        ...extra,
      };
      Map<String, Object?> preference([
        Map<String, Object?> extra = const {},
      ]) => {
        'id': 'p1',
        'subject': 'pattern',
        'value': 'stripes',
        'stance': 'like',
        'occasions': <String>[],
        'inspiration_id': 'i1',
        'created_at': '2026-11-01T10:00:00.000Z',
        'updated_at': '2026-11-01T10:00:00.000Z',
        ...extra,
      };
      Map<String, Object?> style({
        List<Object?>? inspirations,
        List<Object?>? preferences,
      }) => {
        'inspirations': inspirations ?? [inspiration()],
        'preferences': preferences ?? [preference()],
      };
      final base = ok(
        BackupCodec.decode(withJson(zip, 'data/style.json', style())),
      );
      expect(base.history.inspirations.single.palette, [0x1F2A44]);
      expect(
        base.history.inspirations.single.proportions,
        isEmpty,
        reason: 'ficheiros v4 antigos não têm proporções',
      );
      expect(base.history.preferences.single.inspirationId, 'i1');
      expect(base.summary.inspirations, 1);
      expect(base.summary.preferences, 1);
      final cases = <String, Object?>{
        'sem título nem link': style(
          inspirations: [
            inspiration({'title': null, 'source_url': null}),
          ],
        ),
        'link javascript': style(
          inspirations: [
            inspiration({'source_url': 'javascript:alert(1)'}),
          ],
        ),
        'título por aparar': style(
          inspirations: [
            inspiration({'title': ' x '}),
          ],
        ),
        'cor fora do RGB': style(
          inspirations: [
            inspiration({
              'palette': [0x1000000],
            }),
          ],
        ),
        'cor repetida': style(
          inspirations: [
            inspiration({
              'palette': [1, 1],
            }),
          ],
        ),
        'formalidade desconhecida': style(
          inspirations: [
            inspiration({'formality': 'gala'}),
          ],
        ),
        'padrão repetido': style(
          inspirations: [
            inspiration({
              'patterns': ['stripes', 'stripes'],
            }),
          ],
        ),
        'proporção desconhecida': style(
          inspirations: [
            inspiration({
              'proportions': ['oversized'],
            }),
          ],
        ),
        'proporções que não são lista': style(
          inspirations: [
            inspiration({'proportions': 'long_layer'}),
          ],
        ),
        'inspiração repetida': style(
          inspirations: [inspiration(), inspiration()],
        ),
        'valor que não é do assunto': style(
          preferences: [
            preference({'value': 'knit'}),
          ],
        ),
        'posição desconhecida': style(
          preferences: [
            preference({'stance': 'love'}),
          ],
        ),
        'origem que não está no backup': style(
          preferences: [
            preference({'inspiration_id': 'outra'}),
          ],
        ),
        'sem preferências': {'inspirations': <Object?>[]},
      };
      for (final MapEntry(:key, :value) in cases.entries) {
        expect(
          problem(withJson(zip, 'data/style.json', value)),
          isA<CorruptBackup>(),
          reason: key,
        );
      }
    });

    test('conjunto inválido ou com peça que não está no backup', () {
      final garment = (jsonIn(zip, 'data/garments.json')['garments']! as List)
          .cast<Map<String, Object?>>()
          .first['id'];
      Map<String, Object?> outfit({
        Object? name,
        List<Object?> occasions = const [],
        List<Object?>? items,
      }) => {
        'outfits': [
          {
            'id': 'o1',
            'name': name,
            'occasions': occasions,
            'items':
                items ??
                [
                  {'garment_id': garment, 'role': 'main_top'},
                ],
            'created_at': '2026-11-01T10:00:00.000Z',
            'updated_at': '2026-11-01T10:00:00.000Z',
          },
        ],
      };
      expect(
        ok(BackupCodec.decode(withJson(zip, 'data/outfits.json', outfit())))
            .history
            .outfits,
        hasLength(1),
        reason: 'o caso base é válido',
      );
      final cases = <String, Map<String, Object?>>{
        'peça de fora': outfit(
          items: [
            {'garment_id': 'outra', 'role': 'main_top'},
          ],
        ),
        'papel desconhecido': outfit(
          items: [
            {'garment_id': garment, 'role': 'capa'},
          ],
        ),
        'chave a mais': outfit(
          items: [
            {'garment_id': garment, 'role': 'main_top', 'x': 1},
          ],
        ),
        'peça repetida': outfit(
          items: [
            {'garment_id': garment, 'role': 'main_top'},
            {'garment_id': garment, 'role': 'accessory'},
          ],
        ),
        'sem peças': outfit(items: []),
        'nome vazio': outfit(name: ' '),
        'nome longo': outfit(name: 'x' * 121),
        'ocasião desconhecida': outfit(occasions: ['praia']),
      };
      for (final MapEntry(:key, :value) in cases.entries) {
        expect(
          problem(withJson(zip, 'data/outfits.json', value)),
          isA<CorruptBackup>(),
          reason: key,
        );
      }
    });

    test('histórico que refere uma peça que não está no backup', () {
      final history = jsonIn(zip, 'data/history.json');
      final cases = <String, Map<String, Object?>>{
        'utilização': {
          ...history,
          'wear_events': [
            {
              'id': 'w1',
              'worn_on': '2026-11-01',
              'garment_ids': ['outra'],
              'created_at': '2026-11-01T10:00:00.000Z',
            },
          ],
        },
        'limpeza': {
          ...history,
          'cleaning_events': [
            {
              'id': 'c1',
              'garment_id': 'outra',
              'cleaned_on': '2026-11-01',
              'created_at': '2026-11-01T10:00:00.000Z',
            },
          ],
        },
        'valor fora do limite': {
          ...history,
          'care_policies': [
            {
              'scope': 'category',
              'target': 'shirt',
              'laundry_after': 99,
              'rotation_days': null,
            },
          ],
        },
        'categoria desconhecida': {
          ...history,
          'care_policies': [
            {
              'scope': 'category',
              'target': 'capa',
              'laundry_after': 1,
              'rotation_days': null,
            },
          ],
        },
      };
      for (final MapEntry(:key, :value) in cases.entries) {
        expect(
          problem(withJson(zip, 'data/history.json', value)),
          isA<CorruptBackup>(),
          reason: key,
        );
      }
    });
  });

  group('histórico (v2)', () {
    late PowerSyncWearRepository wear;
    late PowerSyncCareRepository care;
    final today = CalendarDay(2026, 11, 3);

    setUp(() {
      final clock = FixedClock(DateTime.utc(2026, 11, 3, 12));
      wear = PowerSyncWearRepository(db: db, ownerId: 'user-a', clock: clock);
      care = PowerSyncCareRepository(db: db, ownerId: 'user-a', clock: clock);
    });

    test('ida e volta: só o ativo e só das peças exportadas', () async {
      final top = (await add(
        const GarmentDraft(category: GarmentCategory.tShirt),
      )).id;
      final gone = (await add(
        const GarmentDraft(category: GarmentCategory.shirt),
      )).id;
      final kept = ok(await wear.recordWear(today.addDays(-1), {top, gone}));
      ok(await wear.recordWear(today.addDays(-3), {gone}));
      final undone = ok(await wear.recordWear(today, {top}));
      ok(await wear.voidWear(undone.id));
      final cleaned = ok(await care.recordCleaning(top, today));
      ok(await care.recordCleaning(gone, today));
      ok(await care.setCategoryRotation(GarmentCategory.tShirt, 4));
      ok(await care.setGarmentLaundry(top, 0));
      ok(await care.setGarmentLaundry(gone, 3));
      ok(await repo.deleteGarment(gone));

      final zip = await export();
      final h = ok(BackupCodec.decode(zip)).history;

      expect(h.wears.single.id, kept.id);
      expect(h.wears.single.wornOn, today.addDays(-1));
      expect(h.wears.single.garmentIds, [top]);
      expect(h.cleanings.single.id, cleaned.id);
      expect(h.cleanings.single.garmentId, top);
      expect(
        [
          for (final p in h.policies)
            (p.scope, p.target, p.laundryAfter, p.rotationDays),
        ],
        unorderedEquals([
          (PolicyScope.category, 't_shirt', null, 4),
          (PolicyScope.garment, top.value, 0, null),
        ]),
      );
      final counts = manifestOf(zip)['counts']! as Map;
      expect(counts['wear_events'], 1);
      expect(counts['cleaning_events'], 1);
      expect(counts['care_policies'], 2);
    });

    test('backup v1 (sem histórico) continua a ser lido', () async {
      await add(const GarmentDraft(category: GarmentCategory.shirt));
      final v1 = downgrade(await export(), 1, [
        'data/history.json',
        'data/outfits.json',
        'data/style.json',
      ]);
      final contents = ok(BackupCodec.decode(v1));
      expect(contents.garments, hasLength(1));
      expect(contents.history.wears, isEmpty);
    });
  });

  group('conjuntos (v3)', () {
    late PowerSyncOutfitRepository outfits;

    setUp(() {
      outfits = PowerSyncOutfitRepository(
        db: db,
        ownerId: 'user-a',
        clock: FixedClock(DateTime.utc(2026, 11, 3, 12)),
      );
    });

    test('ida e volta: só os ativos e sem as peças eliminadas', () async {
      final top = (await add(
        const GarmentDraft(category: GarmentCategory.tShirt),
      )).id;
      final shoes = (await add(
        const GarmentDraft(category: GarmentCategory.sneakers),
      )).id;
      final gone = (await add(
        const GarmentDraft(category: GarmentCategory.trousers),
      )).id;
      final kept = ok(
        await outfits.createOutfit(
          OutfitDraft(
            name: 'Sexta',
            occasions: const {Occasion.casual, Occasion.evening},
            items: [
              OutfitItem(top, OutfitRole.mainTop),
              OutfitItem(gone, OutfitRole.bottom),
              OutfitItem(shoes, OutfitRole.footwear),
            ],
          ),
        ),
      );
      ok(
        await outfits.createOutfit(
          OutfitDraft(items: [OutfitItem(gone, OutfitRole.bottom)]),
        ),
      );
      final deleted = ok(
        await outfits.createOutfit(
          OutfitDraft(items: [OutfitItem(top, OutfitRole.mainTop)]),
        ),
      );
      ok(await outfits.deleteOutfit(deleted.id));
      ok(await repo.deleteGarment(gone));

      final zip = await export();
      final contents = ok(BackupCodec.decode(zip));
      final o = contents.history.outfits.single;
      expect(o.id, kept.id);
      expect(o.name, 'Sexta');
      expect(o.occasions, {Occasion.casual, Occasion.evening});
      expect(o.items, [
        OutfitItem(top, OutfitRole.mainTop),
        OutfitItem(shoes, OutfitRole.footwear),
      ]);
      expect(contents.summary.outfits, 1);
      expect((manifestOf(zip)['counts']! as Map)['outfits'], 1);
    });

    test('backup v2 (sem conjuntos) continua a ser lido', () async {
      await add(const GarmentDraft(category: GarmentCategory.shirt));
      final v2 = downgrade(await export(), 2, [
        'data/outfits.json',
        'data/style.json',
      ]);
      final contents = ok(BackupCodec.decode(v2));
      expect(contents.garments, hasLength(1));
      expect(contents.history.outfits, isEmpty);
    });
  });

  group('estilo (v4)', () {
    late PowerSyncInspirationRepository inspirations;
    late PowerSyncPreferenceRepository preferences;

    setUp(() {
      final clock = FixedClock(DateTime.utc(2026, 11, 3, 12));
      inspirations = PowerSyncInspirationRepository(
        db: db,
        ownerId: 'user-a',
        clock: clock,
      );
      preferences = PowerSyncPreferenceRepository(
        db: db,
        ownerId: 'user-a',
        clock: clock,
      );
    });

    test(
      'ida e volta: só os ativos; origem eliminada vai sem origem',
      () async {
        final kept = ok(
          await inspirations.createInspiration(
            InspirationDraft(
              title: 'Neutros',
              sourceUrl: 'https://example.com/a',
              palette: [ReferenceColor.navy.rgb],
              formality: Formality.smartCasual,
              occasions: const {Occasion.workCasual},
              proportions: const {Proportion.longLayer},
            ),
          ),
        );
        final gone = ok(
          await inspirations.createInspiration(
            const InspirationDraft(
              title: 'Riscas',
              patterns: {GarmentPattern.stripes},
            ),
          ),
        );
        ok(
          await preferences.createPreferences(
            PreferenceDraft.fromInspiration(kept),
          ),
        );
        ok(
          await preferences.createPreferences(
            PreferenceDraft.fromInspiration(gone),
          ),
        );
        final avoided = ok(
          await preferences.createPreference(
            const PreferenceDraft(
              subject: PreferenceSubject.combo,
              value: 'tonal',
              stance: PreferenceStance.avoid,
            ),
          ),
        );
        ok(await preferences.deletePreference(avoided.id));
        ok(await inspirations.deleteInspiration(gone.id));

        final zip = await export();
        final contents = ok(BackupCodec.decode(zip));
        final i = contents.history.inspirations.single;
        expect(i.id, kept.id);
        expect(i.sourceUrl, 'https://example.com/a');
        expect(i.formality, Formality.smartCasual);
        expect(i.proportions, {Proportion.longLayer});
        final prefs = contents.history.preferences;
        expect(
          [for (final p in prefs) '${p.subject.id}:${p.value}'],
          unorderedEquals([
            'color:${ReferenceColor.navy.rgb}',
            'formality:smart_casual',
            'pattern:stripes',
          ]),
        );
        StylePreference about(PreferenceSubject s) =>
            prefs.firstWhere((p) => p.subject == s);
        expect(about(PreferenceSubject.color).inspirationId, kept.id);
        expect(about(PreferenceSubject.color).occasions, {Occasion.workCasual});
        expect(
          about(PreferenceSubject.pattern).inspirationId,
          isNull,
          reason: 'a origem foi eliminada',
        );
        final counts = manifestOf(zip)['counts']! as Map;
        expect(counts['inspirations'], 1);
        expect(counts['style_preferences'], 3);
      },
    );

    group('imagens (v5)', () {
      test('a imagem vai com a inspiração e é verificada', () async {
        final i = ok(
          await inspirations.createInspiration(
            const InspirationDraft(title: 'Com imagem'),
          ),
        );
        final image = ok(await inspirations.setImage(i.id, photo(7))).image!;
        ok(
          await inspirations.createInspiration(
            const InspirationDraft(title: 'Sem imagem'),
          ),
        );
        final zip = await export();
        expect(manifestOf(zip)['version'], 5);
        final contents = ok(BackupCodec.decode(zip));
        expect(contents.summary.photos, 0, reason: 'não são peças');
        expect(contents.summary.inspirationImages, 1);
        final withImage = contents.history.inspirations.firstWhere(
          (x) => x.id == i.id,
        );
        expect(withImage.image, image);
        expect(
          contents.photoFiles[(image.id, PhotoVariant.main)],
          photo(7).main,
        );

        final main = BackupFormat.photoPath(image.id, PhotoVariant.main);
        expect(
          BackupCodec.decode(downgrade(zip, 5, [main])),
          isA<Err<BackupContents, BackupProblem>>(),
          reason: 'imagem em falta',
        );
        final style = jsonIn(zip, BackupFormat.stylePath);
        final altered = [
          for (final x in style['inspirations']! as List)
            {
              ...(x as Map<String, Object?>),
              if (x['image'] != null)
                'image': {
                  ...(x['image']! as Map<String, Object?>),
                  'sha256': 'ab' * 32,
                },
            },
        ];
        expect(
          BackupCodec.decode(
            withJson(zip, BackupFormat.stylePath, {
              ...style,
              'inspirations': altered,
            }),
          ),
          isA<Err<BackupContents, BackupProblem>>(),
          reason: 'imagem alterada',
        );
        final orphan = [
          for (final x in style['inspirations']! as List)
            {...(x as Map<String, Object?>), 'image': null},
        ];
        expect(
          BackupCodec.decode(
            withJson(zip, BackupFormat.stylePath, {
              ...style,
              'inspirations': orphan,
            }),
          ),
          isA<Err<BackupContents, BackupProblem>>(),
          reason: 'ficheiros sem dono',
        );
      });

      test('sem a imagem local nem cloud, a exportação avisa', () async {
        final i = ok(
          await inspirations.createInspiration(
            const InspirationDraft(title: 'x'),
          ),
        );
        final image = ok(await inspirations.setImage(i.id, photo(7))).image!;
        await db.execute('DELETE FROM photo_files');
        final result = await BackupExporter(db: db).export();
        expect(
          result,
          isA<Err<Uint8List, BackupProblem>>().having(
            (e) => e.failure,
            'failure',
            isA<MissingPhotos>(),
          ),
        );
        final remote = await BackupExporter(
          db: db,
          remote: (p, v) async => p.id == image.id ? photo(7).bytesOf(v) : null,
        ).export();
        expect(remote, isA<Ok<Uint8List, BackupProblem>>());
      });

      test('backup v4 (sem imagens) continua a ser lido', () async {
        ok(
          await inspirations.createInspiration(
            const InspirationDraft(title: 'x'),
          ),
        );
        final v4 = downgrade(await export(), 4, const []);
        final contents = ok(BackupCodec.decode(v4));
        expect(contents.history.inspirations.single.image, isNull);
      });
    });

    test('backup v3 (sem estilo) continua a ser lido', () async {
      ok(
        await inspirations.createInspiration(
          const InspirationDraft(title: 'x'),
        ),
      );
      final v3 = downgrade(await export(), 3, ['data/style.json']);
      final contents = ok(BackupCodec.decode(v3));
      expect(contents.history.inspirations, isEmpty);
      expect(contents.summary.inspirations, 0);
    });
  });

  test('nome do ficheiro com data e hora local', () {
    expect(
      backupFileName(DateTime(2026, 11, 3, 9, 5)),
      'guarda-roupa-2026-11-03-0905',
    );
  });
}
