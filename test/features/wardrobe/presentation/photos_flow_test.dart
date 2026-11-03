import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guarda_roupa/features/wardrobe/application/photo_providers.dart';
import 'package:guarda_roupa/features/wardrobe/data/garment_row.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment_photo.dart';
import 'package:guarda_roupa/features/wardrobe/domain/photo_picker.dart';
import 'package:powersync/powersync.dart';
import 'package:crypto/crypto.dart';

import '../../../support/app_harness.dart';
import '../../../support/fake_photos.dart';
import '../../../support/test_database.dart';
import 'wardrobe_flow_test.dart' show addGarment, openWardrobe;

final _photo = find.byType(Image);

Future<({PowerSyncDatabase db, FakePhotoPicker picker})> start(
  WidgetTester tester, {
  FakePhotoStorage? storage,
}) async {
  final picker = FakePhotoPicker();
  final app = await pumpApp(
    tester,
    overrides: [
      photoPickerProvider.overrideWithValue(picker),
      photoStorageProvider.overrideWithValue(storage),
    ],
  );
  await openWardrobe(tester);
  return (db: app.db, picker: picker);
}

Future<List<String?>> kinds(WidgetTester tester, PowerSyncDatabase db) async =>
    [
      for (final op in (await tester.runAsync(() => pendingOperations(db)))!)
        op['kind'] as String?,
    ];

Future<void> openGarment(WidgetTester tester, String name) async {
  await tester.tap(find.text(name));
  await settle(tester);
}

void main() {
  testWidgets('peça nova com fotografia da galeria', (tester) async {
    final app = await start(tester);
    app.picker.next.add(testPng(width: 2000, height: 1500));

    await tester.tap(find.text('Adicionar peça'));
    await settle(tester);
    await tester.tap(find.byKey(const Key('photo-gallery')));
    await settleUntil(tester, _photo);
    expect(app.picker.sources, [PhotoSource.gallery]);

    await tester.tap(find.byKey(const Key('garment-category')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Camisa').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('garment-save')));
    await settleUntil(
      tester,
      find.byKey(const Key('garment-save')),
      gone: true,
    );

    // A miniatura aparece na lista, lida da cópia local.
    await settleUntil(tester, _photo);
    expect(_photo, findsOneWidget);
    expect(await kinds(tester, app.db), ['create', 'attach_photo']);
  });

  testWidgets('na peça existente: câmara adiciona, remover desliga', (
    tester,
  ) async {
    final app = await start(tester);
    await addGarment(tester, category: 'T-shirt', name: 'Branca');
    await openGarment(tester, 'Branca');

    app.picker.next.add(testPng());
    await tester.tap(find.byKey(const Key('photo-camera')));
    await settleUntil(tester, _photo);
    expect(app.picker.sources, [PhotoSource.camera]);
    expect(await kinds(tester, app.db), ['create', 'attach_photo']);

    await tester.tap(find.byKey(const Key('photo-remove-0')));
    await settleUntil(tester, _photo, gone: true);
    expect(await kinds(tester, app.db), [
      'create',
      'attach_photo',
      'detach_photo',
    ]);
  });

  testWidgets('cancelar não faz nada; HEIC e permissão têm mensagem', (
    tester,
  ) async {
    final app = await start(tester);
    await addGarment(tester, category: 'T-shirt', name: 'Branca');
    await openGarment(tester, 'Branca');

    app.picker.next.add(null); // cancelado
    await tester.tap(find.byKey(const Key('photo-gallery')));
    await settle(tester);
    expect(find.byType(SnackBar), findsNothing);

    app.picker.next.add(
      Uint8List.fromList([0, 0, 0, 24, ...'ftypheic'.codeUnits, 0, 0, 0, 0]),
    );
    await tester.tap(find.byKey(const Key('photo-gallery')));
    await settleUntil(tester, find.byType(SnackBar));
    expect(
      find.textContaining('HEIC ainda não são suportadas'),
      findsOneWidget,
    );

    ScaffoldMessenger.of(tester.element(find.byType(ListView)))
        .removeCurrentSnackBar();
    await tester.pumpAndSettle();
    app.picker.failWith = Exception('camera_access_denied');
    await tester.tap(find.byKey(const Key('photo-camera')));
    await settleUntil(tester, find.byType(SnackBar));
    expect(find.textContaining('Verifica as permissões'), findsOneWidget);

    expect(await kinds(tester, app.db), ['create'], reason: 'nada ligado');
  });

  testWidgets('foto de outro dispositivo é descarregada e fica em cache', (
    tester,
  ) async {
    final thumb = testPng(width: 8, height: 8);
    final main = testPng(width: 16, height: 16);
    const photoId = 'a0000000-0000-0000-0000-000000000001';
    final storage = FakePhotoStorage()
      ..files['user-a/$photoId/thumb.jpg'] = thumb
      ..files['user-a/$photoId/main.jpg'] = main;
    final app = await start(tester, storage: storage);

    // Como se viesse da sincronização: metadados sem bytes locais.
    await tester.runAsync(
      () => app.db.execute(
        'INSERT INTO garments (id, owner_id, category, name, availability, '
        'photos, created_at, updated_at, version) '
        "VALUES ('g1', 'user-a', 'shirt', 'Do iPhone', 'available', ?, "
        "'2026-11-03T10:00:00Z', '2026-11-03T10:00:00Z', 1)",
        [
          jsonEncode(
            GarmentRow.photosJson([
              GarmentPhoto(
                id: photoId,
                width: 16,
                height: 16,
                bytes: main.length,
                thumbBytes: thumb.length,
                sha256: sha256.convert(main).toString(),
              ),
            ]),
          ),
        ],
      ),
    );
    await settleUntil(tester, _photo);
    expect(storage.downloads, ['user-a/$photoId/thumb.jpg']);

    final cached = await tester.runAsync(
      () => app.db.getAll('SELECT variant FROM photo_files'),
    );
    expect(cached!.map((r) => r['variant']), [PhotoVariant.thumb.id]);
  });

  testWidgets('sem cópia local nem cloud mostra um marcador', (tester) async {
    final app = await start(tester);
    await tester.runAsync(
      () => app.db.execute(
        'INSERT INTO garments (id, owner_id, category, name, availability, '
        'photos, created_at, updated_at, version) '
        "VALUES ('g1', 'user-a', 'shirt', 'Offline', 'available', ?, "
        "'2026-11-03T10:00:00Z', '2026-11-03T10:00:00Z', 1)",
        [
          jsonEncode([
            {
              'id': 'a0000000-0000-0000-0000-000000000002',
              'width': 1,
              'height': 1,
              'bytes': 1,
              'thumb_bytes': 1,
              'sha256': 'x' * 64,
            },
          ]),
        ],
      ),
    );
    await settleUntil(tester, find.text('Offline'));
    expect(find.byIcon(Icons.image_outlined), findsOneWidget);
    expect(_photo, findsNothing);
  });
}
