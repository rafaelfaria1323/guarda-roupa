import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:guarda_roupa/features/account_sync/data/operation_upload_queue.dart';
import 'package:guarda_roupa/features/inspirations/data/powersync_inspiration_repository.dart';
import 'package:guarda_roupa/features/inspirations/domain/inspiration.dart';
import 'package:guarda_roupa/features/inspirations/domain/inspiration_repository.dart';

import 'dart:typed_data';

import 'package:guarda_roupa/features/wardrobe/data/photo_files.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment_attributes.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment_photo.dart';
import 'package:guarda_roupa/features/wardrobe/domain/reference_color.dart';
import 'package:powersync/powersync.dart';

import '../../support/test_database.dart';
import '../account_sync/data/operation_upload_queue_test.dart'
    show ScriptedUploader;
import '../wardrobe/domain/fakes.dart';
import '../wear/wear_repository_test.dart' show failureOf, ok;

Future<List<Map<String, Object?>>> styleOperations(PowerSyncDatabase db) async {
  final batch = await db.getCrudBatch(limit: 1000);
  return [
    for (final e in batch?.crud ?? const <CrudEntry>[])
      if (e.table == 'style_operations') {'id': e.id, ...?e.opData},
  ];
}

Map<String, Object?> dataOf(Map<String, Object?> op) =>
    jsonDecode(op['data']! as String) as Map<String, Object?>;

void main() {
  group('regras', () {
    test('link sem esquema ganha https; outros esquemas não passam', () {
      expect(
        InspirationRules.normalizeUrl(' pinterest.com/pin/1 '),
        'https://pinterest.com/pin/1',
      );
      expect(InspirationRules.normalizeUrl('  '), isNull);
      for (final bad in [
        'javascript:alert(1)',
        'ftp://example.com',
        'https://a b.com',
        'https://',
      ]) {
        expect(
          InspirationRules.validate(InspirationDraft(sourceUrl: bad)),
          InspirationProblem.invalidUrl,
          reason: bad,
        );
      }
    });

    test('sem título nem link não identifica nada', () {
      expect(
        InspirationRules.validate(
          const InspirationDraft(title: '  ', notes: 'x').normalized(),
        ),
        InspirationProblem.empty,
      );
    });

    test('domínio para mostrar', () {
      final i = Inspiration(
        id: 'i',
        sourceUrl: 'https://www.pinterest.com/pin/1',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );
      expect(i.sourceHost, 'pinterest.com');
    });
  });

  group('repositório', () {
    late PowerSyncDatabase db;
    late PowerSyncInspirationRepository repo;

    setUp(() async {
      db = await openTestDatabase();
      repo = PowerSyncInspirationRepository(
        db: db,
        ownerId: 'user-a',
        clock: FixedClock(DateTime.utc(2026, 11, 3, 12)),
      );
    });

    test('cria com link e etiquetas; não cria peças', () async {
      final created = ok(
        await repo.createInspiration(
          InspirationDraft(
            title: ' Neutros ',
            sourceUrl: 'pinterest.com/pin/1',
            palette: [ReferenceColor.white.rgb, ReferenceColor.navy.rgb],
            formality: Formality.smartCasual,
            occasions: const {Occasion.workCasual},
            textures: const {SurfaceTexture.knit},
          ),
        ),
      );
      expect(created.title, 'Neutros');
      expect(created.sourceUrl, 'https://pinterest.com/pin/1');
      final listed = await repo.watchInspirations().first;
      expect(listed.single.palette, [0xFFFFFF, 0x1F2A44]);
      expect(listed.single.formality, Formality.smartCasual);
      expect(listed.single.textures, {SurfaceTexture.knit});
      expect((await db.get('SELECT count(*) AS n FROM garments'))['n'], 0);

      final op = (await styleOperations(db)).single;
      expect(op['kind'], 'create_inspiration');
      expect(op['entity_id'], created.id);
      expect(dataOf(op), {
        'title': 'Neutros',
        'source_url': 'https://pinterest.com/pin/1',
        'palette': [0xFFFFFF, 0x1F2A44],
        'formality': 'smart_casual',
        'textures': ['knit'],
        'occasions': ['work_casual'],
      }, reason: 'campos vazios não vão');
    });

    test('só link é uma referência válida, sem etiquetas inventadas', () async {
      final i = ok(
        await repo.createInspiration(
          const InspirationDraft(sourceUrl: 'https://example.com/look'),
        ),
      );
      expect(i.title, isNull);
      expect(i.hasTags, false);
    });

    test('inválido não escreve nada', () async {
      expect(
        failureOf(
          await repo.createInspiration(
            const InspirationDraft(sourceUrl: 'javascript:alert(1)'),
          ),
        ),
        isA<InvalidInspiration>(),
      );
      expect(
        failureOf(
          await repo.createInspiration(
            InspirationDraft(
              title: 'x',
              palette: [for (final c in ReferenceColor.values) c.rgb],
            ),
          ),
        ),
        isA<InvalidInspiration>(),
      );
      expect(await repo.watchInspirations().first, isEmpty);
      expect(await styleOperations(db), isEmpty);
    });

    test('editar envia só os campos que mudaram (null apaga)', () async {
      final i = ok(
        await repo.createInspiration(
          const InspirationDraft(
            title: 'Riscas',
            formality: Formality.relaxed,
            patterns: {GarmentPattern.stripes},
          ),
        ),
      );
      ok(
        await repo.updateInspiration(
          i.id,
          InspirationDraft(
            title: i.title,
            notes: 'verão',
            patterns: i.patterns,
          ),
        ),
      );
      ok(
        await repo.updateInspiration(
          i.id,
          (await reload(repo, i.id)).toDraft(),
        ),
      );
      final ops = await styleOperations(db);
      expect(ops.map((o) => o['kind']), [
        'create_inspiration',
        'edit_inspiration',
      ], reason: 'sem alterações não há operação');
      expect(dataOf(ops.last), {'notes': 'verão', 'formality': null});
      final after = await reload(repo, i.id);
      expect(after.formality, isNull);
      expect(after.patterns, {GarmentPattern.stripes});
    });

    test('eliminar sai da lista; repetir é inofensivo', () async {
      final i = ok(
        await repo.createInspiration(const InspirationDraft(title: 'x')),
      );
      ok(await repo.deleteInspiration(i.id));
      ok(await repo.deleteInspiration(i.id));
      expect(await repo.watchInspirations().first, isEmpty);
      expect(
        failureOf(
          await repo.updateInspiration(
            i.id,
            const InspirationDraft(title: 'y'),
          ),
        ),
        isA<InspirationNotFound>(),
      );
      expect((await styleOperations(db)).map((o) => o['kind']), [
        'create_inspiration',
        'delete_inspiration',
      ]);
    });

    test('a fila envia para apply_style_operation', () async {
      final i = ok(
        await repo.createInspiration(const InspirationDraft(title: 'x')),
      );
      final server = ScriptedUploader()
        ..responses.add({'result': 'rejected', 'reason': 'invalid'});
      await OperationUploadQueue(server).upload(db);
      expect(server.log, ['style create_inspiration']);
      expect(server.received.single['entity_id'], i.id);
      final conflict = await db.get('SELECT * FROM sync_conflicts');
      expect(conflict['garment_id'], i.id);
      expect(conflict['reason'], 'invalid');
    });

    test('proporções: guardadas, editadas e enviadas', () async {
      final i = ok(
        await repo.createInspiration(
          const InspirationDraft(
            title: 'Largo em cima',
            proportions: {Proportion.longLayer, Proportion.allFitted},
          ),
        ),
      );
      expect((await reload(repo, i.id)).proportions, {
        Proportion.allFitted,
        Proportion.longLayer,
      });
      expect(i.hasTags, isTrue);
      ok(
        await repo.updateInspiration(
          i.id,
          const InspirationDraft(title: 'Largo em cima'),
        ),
      );
      final ops = await styleOperations(db);
      expect(dataOf(ops.first)['proportions'], ['all_fitted', 'long_layer']);
      expect(dataOf(ops.last), {'proportions': <Object?>[]});
      expect((await reload(repo, i.id)).proportions, isEmpty);
    });

    test('imagem: ligar, trocar, retirar e eliminar', () async {
      final i = ok(
        await repo.createInspiration(const InspirationDraft(title: 'x')),
      );
      final first = ok(await repo.setImage(i.id, image(1))).image!;
      expect((await reload(repo, i.id)).image, first);
      expect(
        await PhotoFiles.get(db, first.id, PhotoVariant.main),
        image(1).main,
      );
      // Editar o texto não perde a imagem.
      final edited = ok(
        await repo.updateInspiration(i.id, const InspirationDraft(title: 'y')),
      );
      expect(edited.image, first);

      final second = ok(await repo.setImage(i.id, image(2))).image!;
      expect(second.id, isNot(first.id));
      ok(await repo.removeImage(i.id));
      expect((await reload(repo, i.id)).image, isNull);
      // Sem imagem, retirar não faz nada.
      ok(await repo.removeImage(i.id));
      ok(await repo.setImage(i.id, image(3)));
      ok(await repo.deleteInspiration(i.id));

      final ops = await styleOperations(db);
      final third = ops[ops.length - 2];
      expect(
        [for (final o in ops) o['kind']],
        [
          'create_inspiration',
          'set_inspiration_image',
          'edit_inspiration',
          'remove_inspiration_image',
          'set_inspiration_image',
          'remove_inspiration_image',
          'set_inspiration_image',
          'delete_inspiration',
        ],
      );
      expect(dataOf(ops[1])['image'], {
        'id': first.id,
        'width': 800,
        'height': 1000,
        'bytes': 32,
        'thumb_bytes': 8,
        'sha256': '01' * 32,
      });
      expect(dataOf(ops[3]), {'photo_id': first.id});
      expect(dataOf(ops[5]), {'photo_id': second.id});
      final thirdId = (dataOf(third)['image']! as Map)['id'];
      expect(dataOf(ops.last), {'photo_id': thirdId});

      // A fila envia os ficheiros antes de ligar e apaga-os depois de
      // retirar ou eliminar.
      final server = ScriptedUploader();
      await OperationUploadQueue(server).upload(db);
      expect(server.log, [
        'style create_inspiration',
        'upload ${first.id}/main',
        'upload ${first.id}/thumb',
        'style set_inspiration_image',
        'style edit_inspiration',
        // Trocar é uma transação: retirar e ligar, e só depois apagar.
        'style remove_inspiration_image',
        'upload ${second.id}/main',
        'upload ${second.id}/thumb',
        'style set_inspiration_image',
        'remove ${first.id}',
        'style remove_inspiration_image',
        'remove ${second.id}',
        'upload $thirdId/main',
        'upload $thirdId/thumb',
        'style set_inspiration_image',
        'style delete_inspiration',
        'remove $thirdId',
      ]);
      expect(server.files, isEmpty);
      expect((await db.get('SELECT count(*) AS n FROM photo_files'))['n'], 0);
    });

    test('imagem numa inspiração eliminada: não encontrada', () async {
      final i = ok(
        await repo.createInspiration(const InspirationDraft(title: 'x')),
      );
      ok(await repo.deleteInspiration(i.id));
      expect(
        failureOf(await repo.setImage(i.id, image(1))),
        isA<InspirationNotFound>(),
      );
      expect((await db.get('SELECT count(*) AS n FROM photo_files'))['n'], 0);
    });
  });
}

ProcessedPhoto image(int seed) => ProcessedPhoto(
  width: 800,
  height: 1000,
  main: Uint8List.fromList(List.filled(32, seed)),
  thumb: Uint8List.fromList(List.filled(8, seed)),
  sha256: (seed.toRadixString(16).padLeft(2, '0')) * 32,
);

Future<Inspiration> reload(InspirationRepository repo, String id) async =>
    (await repo.watchInspiration(id).first)!;
