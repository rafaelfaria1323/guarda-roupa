import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guarda_roupa/core/domain/result.dart';
import 'package:guarda_roupa/features/local_ai/application/local_ai_providers.dart';
import 'package:guarda_roupa/features/photo_ai/application/label_camera.dart';
import 'package:guarda_roupa/features/photo_ai/application/photo_ai_providers.dart';
import 'package:guarda_roupa/features/photo_ai/domain/photo_reader.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment_attributes.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment_category.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment_color.dart';
import 'package:guarda_roupa/features/wardrobe/domain/photo_picker.dart';
import 'package:guarda_roupa/features/wardrobe/domain/reference_color.dart';
import 'package:powersync/powersync.dart';

import '../../support/app_harness.dart';
import '../../support/fake_label_camera.dart';
import '../../support/fake_models.dart';
import '../../support/fake_photo_reader.dart';
import '../../support/fake_photos.dart';
import '../wardrobe/presentation/batch_add_flow_test.dart' show pickBatch;
import '../wardrobe/presentation/photos_flow_test.dart' show start;

final _shirt = GarmentReading(
  category: GarmentCategory.shirt,
  name: 'Camisa às riscas',
  colors: [
    GarmentColor.create(rgb: ReferenceColor.white.rgb, proportion: 0.6)!,
    GarmentColor.create(rgb: ReferenceColor.navy.rgb, proportion: 0.4)!,
  ],
  pattern: GarmentPattern.stripes,
);

Future<List<Map<String, Object?>>> garments(
  WidgetTester tester,
  PowerSyncDatabase db,
) async => (await tester.runAsync(
  () => db.getAll(
    'select category, name, pattern, wash, tumble_dry, material, care '
    'from garments order by created_at, id',
  ),
))!.map(Map<String, Object?>.of).toList();

void main() {
  testWidgets('várias fotos com o Gemini: categoria, nome e cores', (
    tester,
  ) async {
    final reader = FakePhotoReader(garment: Ok(_shirt));
    final app = await start(
      tester,
      overrides: [activePhotoReaderProvider.overrideWithValue(reader)],
    );
    app.picker.nextMany = [testPng(), testPng(r: 30)];

    await tester.tap(find.byKey(const Key('wardrobe-batch')));
    await settle(tester);
    expect(find.textContaining('Com o Gemini ligado'), findsOneWidget);
    await tester.tap(find.byKey(const Key('batch-pick')));
    await settleUntil(tester, find.byKey(const Key('batch-more')));

    expect(reader.garmentPhotos, hasLength(2));
    expect(await garments(tester, app.db), [
      for (var i = 0; i < 2; i++)
        {
          'category': 'shirt',
          'name': 'Camisa às riscas',
          'pattern': 'stripes',
          'wash': null,
          'tumble_dry': null,
          'material': null,
          'care': null,
        },
    ]);
  });

  testWidgets('sem quota do Gemini: segue pelo aparelho e para de pedir', (
    tester,
  ) async {
    final reader = FakePhotoReader(garment: const Err(PhotoReadFailure.busy));
    final app = await start(
      tester,
      overrides: [
        activePhotoReaderProvider.overrideWithValue(reader),
        categorySuggesterProvider.overrideWithValue(
          FakeCategorySuggester(const [GarmentCategory.jeans]),
        ),
      ],
    );
    app.picker.nextMany = [testPng(), testPng(r: 30)];

    await pickBatch(tester);
    expect(reader.garmentPhotos, hasLength(1));
    expect(
      find.textContaining('As restantes fotos seguem sem o Gemini'),
      findsOneWidget,
    );
    expect(
      [for (final g in await garments(tester, app.db)) g['category']],
      ['jeans', 'jeans'],
    );
  });

  testWidgets('peça nova: preencher pela foto e ler a etiqueta', (
    tester,
  ) async {
    final reader = FakePhotoReader(
      garment: Ok(_shirt),
      label: const Ok(
        LabelReading(
          wash: WashCare.machine30,
          tumbleDry: false,
          material: '100% algodão',
        ),
      ),
    );
    final camera = FakeLabelCamera();
    final app = await start(
      tester,
      overrides: [
        activePhotoReaderProvider.overrideWithValue(reader),
        labelCameraProvider.overrideWithValue(() => camera),
      ],
    );
    await tester.tap(find.text('Adicionar peça'));
    await settle(tester);
    // Sem foto, só a etiqueta.
    expect(find.byKey(const Key('garment-fill-from-photo')), findsNothing);

    app.picker.next.add(testPng());
    await tester.tap(find.byKey(const Key('photo-gallery')));
    await settleUntil(tester, find.byKey(const Key('garment-fill-from-photo')));
    await tester.tap(find.byKey(const Key('garment-fill-from-photo')));
    await settleUntil(tester, find.text('Camisa às riscas'));
    expect(
      find.text('Preenchido pela foto. Confirma antes de guardar.'),
      findsOneWidget,
    );

    // Desfazer volta ao que estava.
    await tester.tap(find.text('Desfazer'));
    await settleUntil(tester, find.text('Camisa às riscas'), gone: true);
    await tester.tap(find.byKey(const Key('garment-fill-from-photo')));
    await settleUntil(tester, find.text('Camisa às riscas'));

    final label = find.byKey(const Key('garment-read-label'));
    await tester.scrollUntilVisible(
      label,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await settle(tester);
    await tester.tap(label);
    // O ecrã "Ler etiqueta": passos, câmara ao vivo e até 3 fotos.
    await settleUntil(tester, find.byKey(const Key('label-scan-preview')));
    expect(find.textContaining('Não é o rótulo de couro'), findsOneWidget);
    final capture = find.byKey(const Key('label-scan-capture'));
    await tester.tap(capture);
    await settleUntil(tester, find.byKey(const Key('label-scan-photo-0')));
    await tester.tap(capture);
    await settleUntil(tester, find.byKey(const Key('label-scan-photo-1')));
    expect(find.text('Ler 2 fotos'), findsOneWidget);
    await tester.tap(find.byKey(const Key('label-scan-read')));
    await settleUntil(tester, find.text('100% algodão'));
    expect(reader.labelReads, [2]);
    expect(camera.captures, 2);
    expect(camera.closed, isTrue);

    await tester.tap(find.byKey(const Key('garment-save')));
    await settleUntil(
      tester,
      find.byKey(const Key('garment-save')),
      gone: true,
    );
    expect(await garments(tester, app.db), [
      {
        'category': 'shirt',
        'name': 'Camisa às riscas',
        'pattern': 'stripes',
        'wash': 'machine_30',
        'tumble_dry': 0,
        'material': '100% algodão',
        'care': null,
      },
    ]);
    // Só uma foto guardada: a da etiqueta não fica.
    final row = await tester.runAsync(
      () => app.db.get('select photos from garments'),
    );
    expect(jsonDecode(row!['photos']! as String) as List, hasLength(1));
  });

  testWidgets('Definições: o Gemini começa desligado e liga-se aqui', (
    tester,
  ) async {
    final reader = FakePhotoReader();
    final app = await pumpApp(
      tester,
      overrides: [photoReaderProvider.overrideWithValue(reader)],
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(Scaffold).first),
    );
    expect(container.read(activePhotoReaderProvider), isNull);

    await tester.tap(find.byTooltip('Definições'));
    await settle(tester);
    final tile = find.byKey(const Key('local-ai-settings'));
    await tester.scrollUntilVisible(
      tile,
      200,
      scrollable: find
          .descendant(
            of: find.byType(ListView).last,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.ensureVisible(tile);
    await tester.pumpAndSettle();
    await tester.tap(tile);
    await settle(tester);
    final toggle = find.byKey(const Key('gemini-photos'));
    await tester.scrollUntilVisible(
      toggle,
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await settle(tester);
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
    await tester.tap(toggle);
    await settle(tester);
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
    expect(container.read(activePhotoReaderProvider), same(reader));
    final row = await tester.runAsync(
      () => app.db.get(
        "select value from local_settings where key = 'gemini_photos'",
      ),
    );
    expect(row!['value'], '1');
  });

  testWidgets('ler etiqueta: rótulo errado, sem câmara e galeria', (
    tester,
  ) async {
    final reader = FakePhotoReader(
      label: const Ok(LabelReading(found: LabelFound.otherLabel)),
    );
    final app = await start(
      tester,
      overrides: [
        activePhotoReaderProvider.overrideWithValue(reader),
        labelCameraProvider.overrideWithValue(
          () => FakeLabelCamera(available: false),
        ),
      ],
    );
    await tester.tap(find.text('Adicionar peça'));
    await settle(tester);
    final label = find.byKey(const Key('garment-read-label'));
    await tester.scrollUntilVisible(
      label,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await settle(tester);
    await tester.tap(label);
    // Sem câmara ao vivo: o botão redondo usa a câmara do sistema.
    await settleUntil(tester, find.byKey(const Key('label-scan-no-camera')));
    app.picker.next.add(testPng(r: 90));
    await tester.tap(find.byKey(const Key('label-scan-capture')));
    await settleUntil(tester, find.byKey(const Key('label-scan-photo-0')));
    expect(app.picker.sources.last, PhotoSource.camera);

    // O rótulo de couro não é a etiqueta: explica e limpa as fotos.
    await tester.tap(find.byKey(const Key('label-scan-read')));
    await settleUntil(tester, find.byKey(const Key('label-scan-message')));
    expect(find.textContaining('rótulo da marca'), findsOneWidget);
    expect(find.byKey(const Key('label-scan-photo-0')), findsNothing);

    // Da galeria, e depois uma etiqueta que se lê.
    reader.label = const Ok(
      LabelReading(found: LabelFound.careLabel, wash: WashCare.hand),
    );
    app.picker.nextMany = [testPng(r: 10), testPng(r: 20)];
    await tester.tap(find.byKey(const Key('label-scan-gallery')));
    await settleUntil(tester, find.byKey(const Key('label-scan-photo-1')));
    await tester.tap(find.byKey(const Key('label-scan-read')));
    await settleUntil(
      tester,
      find.byKey(const Key('label-scan-read')),
      gone: true,
    );
    expect(reader.labelReads, [1, 2]);
    expect(
      find.text('Etiqueta lida. Confirma antes de guardar.'),
      findsOneWidget,
    );
  });
}
