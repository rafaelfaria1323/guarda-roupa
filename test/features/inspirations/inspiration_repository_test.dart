import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:guarda_roupa/features/account_sync/data/operation_upload_queue.dart';
import 'package:guarda_roupa/features/inspirations/data/powersync_inspiration_repository.dart';
import 'package:guarda_roupa/features/inspirations/domain/inspiration.dart';
import 'package:guarda_roupa/features/inspirations/domain/inspiration_repository.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment_attributes.dart';
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
  });
}

Future<Inspiration> reload(InspirationRepository repo, String id) async =>
    (await repo.watchInspiration(id).first)!;
