import 'package:flutter_test/flutter_test.dart';
import 'package:guarda_roupa/features/account_sync/data/operation_upload_queue.dart';
import 'package:guarda_roupa/features/inspirations/data/powersync_inspiration_repository.dart';
import 'package:guarda_roupa/features/inspirations/data/powersync_preference_repository.dart';
import 'package:guarda_roupa/features/inspirations/domain/inspiration.dart';
import 'package:guarda_roupa/features/inspirations/domain/inspiration_repository.dart';
import 'package:guarda_roupa/features/inspirations/domain/style_preference.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment_attributes.dart';
import 'package:guarda_roupa/features/wardrobe/domain/reference_color.dart';
import 'package:powersync/powersync.dart';

import '../../support/test_database.dart';
import '../account_sync/data/operation_upload_queue_test.dart'
    show ScriptedUploader;
import '../wardrobe/domain/fakes.dart';
import '../wear/wear_repository_test.dart' show failureOf, ok;
import 'inspiration_repository_test.dart' show dataOf, styleOperations;

void main() {
  group('regras', () {
    test('valores aceites por assunto', () {
      expect(PreferenceSubject.color.accepts('2042436'), true);
      expect(PreferenceSubject.color.accepts('16777216'), false);
      expect(PreferenceSubject.color.accepts('007'), false);
      expect(PreferenceSubject.color.accepts('azul'), false);
      expect(PreferenceSubject.pattern.accepts('stripes'), true);
      expect(PreferenceSubject.pattern.accepts('knit'), false);
      expect(PreferenceSubject.combo.accepts('tonal'), true);
      expect(PreferenceSubject.formality.accepts('dressy'), true);
    });

    test('de uma inspiração: um "gosto" por etiqueta, no contexto dela', () {
      final i = Inspiration(
        id: 'insp',
        title: 'x',
        palette: [ReferenceColor.navy.rgb],
        formality: Formality.smartCasual,
        patterns: const {GarmentPattern.stripes},
        textures: const {SurfaceTexture.knit},
        occasions: const {Occasion.workCasual},
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );
      final drafts = PreferenceDraft.fromInspiration(i);
      expect(
        [for (final d in drafts) '${d.subject.id}:${d.value}'],
        [
          'color:${ReferenceColor.navy.rgb}',
          'formality:smart_casual',
          'pattern:stripes',
          'texture:knit',
        ],
      );
      expect(drafts.every((d) => d.stance == PreferenceStance.like), true);
      expect(drafts.every((d) => d.inspirationId == 'insp'), true);
      expect(
        drafts.every((d) => d.occasions.single == Occasion.workCasual),
        true,
      );
    });
  });

  group('repositório', () {
    late PowerSyncDatabase db;
    late PowerSyncPreferenceRepository repo;

    setUp(() async {
      db = await openTestDatabase();
      repo = PowerSyncPreferenceRepository(
        db: db,
        ownerId: 'user-a',
        clock: FixedClock(DateTime.utc(2026, 11, 3, 12)),
      );
    });

    const navy = PreferenceDraft(
      subject: PreferenceSubject.color,
      value: '2042436',
      stance: PreferenceStance.like,
    );

    test('cria e lista; a operação leva só o que existe', () async {
      final p = ok(await repo.createPreference(navy));
      expect((await repo.watchPreferences().first).single.value, '2042436');
      final op = (await styleOperations(db)).single;
      expect(op['kind'], 'create_preference');
      expect(op['entity_id'], p.id);
      expect(dataOf(op), {
        'subject': 'color',
        'value': '2042436',
        'stance': 'like',
      });
      expect((await db.get('SELECT count(*) AS n FROM garments'))['n'], 0);
    });

    test('valor inválido ou repetido no mesmo contexto não escreve', () async {
      expect(
        failureOf(
          await repo.createPreference(
            const PreferenceDraft(
              subject: PreferenceSubject.texture,
              value: 'stripes',
              stance: PreferenceStance.avoid,
            ),
          ),
        ),
        isA<InvalidPreference>(),
      );
      final p = ok(await repo.createPreference(navy));
      expect(
        failureOf(
          await repo.createPreference(
            const PreferenceDraft(
              subject: PreferenceSubject.color,
              value: '2042436',
              stance: PreferenceStance.avoid,
            ),
          ),
        ),
        isA<DuplicatePreference>().having((f) => f.existingId, 'id', p.id),
      );
      // Noutro contexto já pode.
      ok(
        await repo.createPreference(
          const PreferenceDraft(
            subject: PreferenceSubject.color,
            value: '2042436',
            stance: PreferenceStance.avoid,
            occasions: {Occasion.evening},
          ),
        ),
      );
      expect(await repo.watchPreferences().first, hasLength(2));
      expect(await styleOperations(db), hasLength(2));
    });

    test('criar várias ignora as repetidas', () async {
      ok(await repo.createPreference(navy));
      final created = ok(
        await repo.createPreferences([
          navy,
          const PreferenceDraft(
            subject: PreferenceSubject.pattern,
            value: 'stripes',
            stance: PreferenceStance.like,
            inspirationId: 'insp',
          ),
        ]),
      );
      expect(created, 1);
      final ops = await styleOperations(db);
      expect(dataOf(ops.last)['inspiration_id'], 'insp');
    });

    test('editar muda só valor, posição e contexto', () async {
      final p = ok(
        await repo.createPreference(
          const PreferenceDraft(
            subject: PreferenceSubject.pattern,
            value: 'stripes',
            stance: PreferenceStance.like,
            inspirationId: 'insp',
          ),
        ),
      );
      final after = ok(
        await repo.updatePreference(
          p.id,
          const PreferenceDraft(
            subject: PreferenceSubject.color, // ignorado
            value: 'stripes',
            stance: PreferenceStance.avoid,
            occasions: {Occasion.workCasual},
          ),
        ),
      );
      expect(after.subject, PreferenceSubject.pattern);
      expect(after.inspirationId, 'insp');
      ok(await repo.updatePreference(p.id, after.toDraft()));
      final ops = await styleOperations(db);
      expect(ops.map((o) => o['kind']), [
        'create_preference',
        'edit_preference',
      ], reason: 'sem alterações não há operação');
      expect(dataOf(ops.last), {
        'stance': 'avoid',
        'occasions': ['work_casual'],
      });
      final listed = (await repo.watchPreference(p.id).first)!;
      expect(listed.stance, PreferenceStance.avoid);
      expect(listed.occasions, {Occasion.workCasual});
    });

    test('eliminar é idempotente; a fila usa apply_style_operation', () async {
      final p = ok(await repo.createPreference(navy));
      ok(await repo.deletePreference(p.id));
      ok(await repo.deletePreference(p.id));
      expect(await repo.watchPreferences().first, isEmpty);
      expect(
        failureOf(await repo.updatePreference(p.id, navy)),
        isA<PreferenceNotFound>(),
      );
      final server = ScriptedUploader();
      await OperationUploadQueue(server).upload(db);
      expect(server.log, [
        'style create_preference',
        'style delete_preference',
      ]);
      expect(server.received.first['entity_id'], p.id);
    });

    test('a preferência fica se a inspiração for eliminada', () async {
      final inspirations = PowerSyncInspirationRepository(
        db: db,
        ownerId: 'user-a',
        clock: FixedClock(DateTime.utc(2026, 11, 3, 12)),
      );
      final i = ok(
        await inspirations.createInspiration(
          const InspirationDraft(
            title: 'x',
            patterns: {GarmentPattern.stripes},
          ),
        ),
      );
      ok(await repo.createPreferences(PreferenceDraft.fromInspiration(i)));
      ok(await inspirations.deleteInspiration(i.id));
      final left = (await repo.watchPreferences().first).single;
      expect(left.value, 'stripes');
      expect(left.inspirationId, i.id);
    });
  });
}
