import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:guarda_roupa/core/domain/result.dart';
import 'package:guarda_roupa/features/account_sync/data/operation_upload_queue.dart';
import 'package:guarda_roupa/features/wardrobe/data/powersync_wardrobe_repository.dart';
import 'package:guarda_roupa/features/wardrobe/domain/availability.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment_category.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment_photo.dart';
import 'package:powersync/powersync.dart';

import '../../../support/test_database.dart';

/// Servidor simulado: devolve respostas programadas e regista o que recebeu.
/// O formato das respostas é o de `apply_garment_operation`, coberto pelos
/// testes SQL (supabase/tests).
final class ScriptedUploader implements OperationUploader {
  final received = <Map<String, Object?>>[];
  final responses = <Map<String, Object?>>[];
  Object? failWith;

  /// Tudo o que chegou ao servidor, pela ordem: operações e ficheiros.
  final log = <String>[];
  final files = <String, Uint8List>{};
  Object? fileFailWith;
  Object? removeFailWith;

  @override
  Future<void> uploadPhotoFile(
    String photoId,
    PhotoVariant variant,
    Uint8List bytes,
  ) async {
    if (fileFailWith case final error?) throw error;
    log.add('upload $photoId/${variant.id}');
    files['$photoId/${variant.id}'] = bytes;
  }

  @override
  Future<void> removePhotoFiles(String photoId) async {
    if (removeFailWith case final error?) throw error;
    log.add('remove $photoId');
    files.removeWhere((k, _) => k.startsWith('$photoId/'));
  }

  @override
  Future<Map<String, Object?>> apply(Map<String, Object?> operation) async {
    if (failWith case final error?) throw error;
    received.add(operation);
    log.add('apply ${operation['kind']}');
    return responses.isEmpty ? {'result': 'applied'} : responses.removeAt(0);
  }
}

void main() {
  late PowerSyncDatabase db;
  late PowerSyncWardrobeRepository repo;
  late ScriptedUploader server;
  late OperationUploadQueue queue;

  setUp(() async {
    db = await openTestDatabase();
    repo = PowerSyncWardrobeRepository(db: db, ownerId: 'user-a');
    server = ScriptedUploader();
    queue = OperationUploadQueue(server);
  });

  Future<Garment> add() async => switch (await repo.addGarment(
    const GarmentDraft(category: GarmentCategory.tShirt, name: 'Branca'),
  )) {
    Ok(:final value) => value,
    Err(:final failure) => fail('$failure'),
  };

  test('envia operações pela ordem, com op_id e dados decodificados', () async {
    final g = await add();
    await repo.setAvailability(g.id, Availability.needsCleaning);

    await queue.upload(db);

    expect(server.received.map((o) => o['kind']), [
      'create',
      'set_availability',
    ]);
    expect(server.received.last['garment_id'], g.id.value);
    expect(server.received.last['data'], {
      'from': 'available',
      'to': 'needs_cleaning',
    });
    expect(server.received.map((o) => o['op_id']).toSet(), hasLength(2));
    expect(await db.getCrudBatch(), isNull, reason: 'fila esvaziada');
  });

  test('conflito e rejeição ficam registados para o utilizador', () async {
    final g = await add();
    await repo.setAvailability(g.id, Availability.available); // sem operação
    await repo.setAvailability(g.id, Availability.washing);
    server.responses.addAll([
      {'result': 'applied'},
      {
        'result': 'conflict',
        'conflicts': [
          {
            'field': 'availability',
            'local': 'washing',
            'remote': 'needs_cleaning',
          },
        ],
      },
    ]);

    await queue.upload(db);

    final conflicts = await db.getAll('SELECT * FROM sync_conflicts');
    expect(conflicts.single['kind'], 'set_availability');
    expect(conflicts.single['result'], 'conflict');
    expect(conflicts.single['details'], contains('needs_cleaning'));
  });

  test('rejeição "deleted" é registada com o motivo', () async {
    await add();
    server.responses.add({'result': 'rejected', 'reason': 'deleted'});
    await queue.upload(db);
    final c = await db.get('SELECT result, reason FROM sync_conflicts');
    expect(c['result'], 'rejected');
    expect(c['reason'], 'deleted');
  });

  test('falha de rede mantém as operações na fila para repetir', () async {
    await add();
    server.failWith = Exception('sem rede');

    await expectLater(queue.upload(db), throwsException);
    expect((await pendingOperations(db)), hasLength(1));

    server.failWith = null;
    await queue.upload(db);
    expect(await db.getCrudBatch(), isNull);
    expect(server.received, hasLength(1));
  });

  test('a repetição envia o mesmo op_id (idempotência no servidor)', () async {
    await add();
    final opId = (await pendingOperations(db)).single['id'];
    server.failWith = Exception('timeout');
    await expectLater(queue.upload(db), throwsException);
    server.failWith = null;
    await queue.upload(db);
    expect(server.received.single['op_id'], opId);
  });

  group('fotografias', () {
    final photo = ProcessedPhoto(
      width: 10,
      height: 10,
      main: _main,
      thumb: _thumb,
      sha256: 'ab',
    );

    Future<String> addPhoto(Garment g) async =>
        switch (await repo.addPhoto(g.id, photo)) {
          Ok(:final value) => value.photos.last.id,
          Err(:final failure) => fail('$failure'),
        };

    test('envia os ficheiros antes de ligar a foto', () async {
      final g = await add();
      final id = await addPhoto(g);
      await queue.upload(db);
      expect(server.log, [
        'apply create',
        'upload $id/main',
        'upload $id/thumb',
        'apply attach_photo',
      ]);
      expect(server.files['$id/main'], _main);
      expect(
        await repo.photoBytes(id, PhotoVariant.main),
        isNotNull,
        reason: 'continua disponível offline',
      );
    });

    test('falha no envio do ficheiro não liga a foto e repete', () async {
      final g = await add();
      await addPhoto(g);
      server.fileFailWith = Exception('sem rede');
      await expectLater(queue.upload(db), throwsException);
      expect(server.log, isNot(contains('apply attach_photo')));
      expect(
        (await pendingOperations(db)).single['kind'],
        'attach_photo',
        reason: 'o create já foi; o attach fica na fila',
      );

      server.fileFailWith = null;
      await queue.upload(db);
      expect(server.log.last, 'apply attach_photo');
      expect(await db.getCrudBatch(), isNull);
    });

    test('remover apaga os ficheiros depois de enviar', () async {
      final g = await add();
      final id = await addPhoto(g);
      await queue.upload(db);
      await repo.removePhoto(g.id, id);
      await queue.upload(db);
      expect(server.log.sublist(server.log.length - 2), [
        'apply detach_photo',
        'remove $id',
      ]);
      expect(server.files, isEmpty);
      expect(await repo.photoBytes(id, PhotoVariant.main), isNull);
    });

    test('adicionar e remover offline: envia tudo pela ordem', () async {
      final g = await add();
      final id = await addPhoto(g);
      await repo.removePhoto(g.id, id);
      await queue.upload(db);
      expect(server.log, [
        'apply create',
        'upload $id/main',
        'upload $id/thumb',
        'apply attach_photo',
        'apply detach_photo',
        'remove $id',
      ]);
      expect(await db.getAll('SELECT * FROM sync_conflicts'), isEmpty);
    });

    test('falha a apagar no Storage não bloqueia a fila', () async {
      final g = await add();
      final id = await addPhoto(g);
      await repo.removePhoto(g.id, id);
      server.removeFailWith = Exception('sem rede');
      await queue.upload(db);
      expect(await db.getCrudBatch(), isNull);
      expect(await repo.photoBytes(id, PhotoVariant.main), isNull);
    });
  });
}

final _main = Uint8List.fromList([1, 2, 3]);
final _thumb = Uint8List.fromList([4]);
