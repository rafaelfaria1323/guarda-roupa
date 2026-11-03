import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guarda_roupa/features/wardrobe/application/photo_providers.dart';
import 'package:guarda_roupa/features/wardrobe/domain/photo_picker.dart';
import 'package:powersync/powersync.dart';

import '../../support/app_harness.dart';
import '../../support/fake_photos.dart';
import '../wardrobe/presentation/wardrobe_flow_test.dart' show inList;
import 'inspiration_repository_test.dart' show styleOperations;
import 'inspiration_flow_test.dart'
    show dismissSnackBar, openStyle, saveInspiration, tapTag;

final _image = find.byType(Image);

Future<List<String>> styleKinds(
  WidgetTester tester,
  PowerSyncDatabase db,
) async {
  final ops = (await tester.runAsync(() => styleOperations(db)))!;
  return [for (final o in ops) o['kind']! as String];
}

void main() {
  testWidgets('imagem só com confirmação de direitos; pendente até guardar; '
      'trocar e retirar; proporções', (tester) async {
    final picker = FakePhotoPicker();
    final (:auth, :db) = await pumpApp(
      tester,
      overrides: [
        photoPickerProvider.overrideWithValue(picker),
        photoStorageProvider.overrideWithValue(null),
      ],
    );
    expect(auth, isNotNull);
    await openStyle(tester);
    await dismissSnackBar(tester);
    await tester.tap(find.byKey(const Key('inspiration-add')));
    await settle(tester);
    await tester.enterText(
      find.byKey(const Key('inspiration-title')),
      'Casaco',
    );

    // Recusar a confirmação não abre a galeria.
    await tapTag(tester, 'inspiration-image-gallery');
    expect(find.text('Imagem tua ou autorizada?'), findsOne);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(picker.sources, isEmpty);

    picker.next.add(testPng(width: 1200, height: 1600));
    await tapTag(tester, 'inspiration-image-gallery');
    await tester.tap(find.byKey(const Key('inspiration-image-rights-confirm')));
    await settleUntil(tester, find.byKey(const Key('inspiration-image')));
    expect(picker.sources, [PhotoSource.gallery]);
    expect(await styleKinds(tester, db), isEmpty, reason: 'ainda pendente');

    await tapTag(tester, 'inspiration-proportion-long_layer');
    await saveInspiration(tester);
    expect(await styleKinds(tester, db), [
      'create_inspiration',
      'set_inspiration_image',
    ]);
    // Miniatura na lista, lida da cópia local; proporção nas etiquetas.
    await settleUntil(tester, _image);
    expect(find.text('Camada comprida'), findsOne);

    // Trocar (já não pergunta de novo neste ecrã) e retirar.
    await tester.tap(inList('Casaco'));
    await settle(tester);
    await settleUntil(tester, find.byKey(const Key('inspiration-image')));
    picker.next.add(testPng(width: 800, height: 800));
    await tapTag(tester, 'inspiration-image-camera');
    await tester.tap(find.byKey(const Key('inspiration-image-rights-confirm')));
    await settle(tester);
    picker.next.add(testPng(width: 900, height: 900));
    // Sem diálogo, o toque vai direto ao processamento (com indicador).
    await tester.tap(find.byKey(const Key('inspiration-image-camera')));
    await settle(tester);
    expect(
      find.byKey(const Key('inspiration-image-rights-confirm')),
      findsNothing,
    );
    expect(picker.sources, [
      PhotoSource.gallery,
      PhotoSource.camera,
      PhotoSource.camera,
    ]);
    await settleUntil(
      tester,
      find.byKey(const Key('inspiration-image-remove')),
    );
    await tapTag(tester, 'inspiration-image-remove');
    await settleUntil(
      tester,
      find.byKey(const Key('inspiration-image')),
      gone: true,
    );
    expect(await styleKinds(tester, db), [
      'create_inspiration',
      'set_inspiration_image',
      'remove_inspiration_image',
      'set_inspiration_image',
      'remove_inspiration_image',
      'set_inspiration_image',
      'remove_inspiration_image',
    ]);
    await tester.tap(find.byType(BackButton));
    await settle(tester);
    expect(_image, findsNothing);
  });
}
