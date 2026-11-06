import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guarda_roupa/features/import/application/import_providers.dart';
import 'package:guarda_roupa/features/import/domain/product_import.dart';
import 'package:guarda_roupa/features/wardrobe/application/photo_providers.dart';
import 'package:guarda_roupa/features/wardrobe/domain/photo_picker.dart';

import '../../support/app_harness.dart';
import '../../support/fake_photos.dart';
import '../import/import_flow_test.dart' show FakeImporter;
import 'inspiration_flow_test.dart'
    show dismissSnackBar, openStyle, saveInspiration;
import 'inspiration_image_flow_test.dart' show styleKinds;
import 'inspiration_repository_test.dart' show dataOf, styleOperations;

InspirationInboxItem pin(String id, {String? title}) => InspirationInboxItem(
  id: id,
  site: 'Pinterest',
  url: 'https://www.pinterest.com/pin/$id/',
  title: title,
  description: 'Blazer e calças largas.',
  createdAt: DateTime.utc(2026, 11, 6),
);

void main() {
  test('linha da caixa: só as inspirações', () {
    final row = {
      'id': 'a',
      'created_at': '2026-11-06T10:00:00Z',
      'url': 'https://pin.it/x',
      'preview': {
        'result': 'ok',
        'kind': 'inspiration',
        'site': 'Pinterest',
        'url': 'https://www.pinterest.com/pin/1/',
        'inspiration': {'title': 'Look', 'description': ' '},
        'via': 'shared',
      },
    };
    final item = InspirationInboxItem.fromJson(row)!;
    expect(item.url, 'https://www.pinterest.com/pin/1/');
    expect(item.title, 'Look');
    expect(item.description, isNull);
    // Uma inspiração não é uma peça, e uma peça não é uma inspiração.
    expect(InboxItem.fromJson(row), isNull);
    expect(
      InspirationInboxItem.fromJson({
        ...row,
        'preview': {'result': 'ok', 'url': 'https://loja.example/p'},
      }),
      isNull,
    );
  });

  testWidgets('Pin do atalho: só o link, ou descartar', (tester) async {
    final importer = FakeImporter()
      ..inspirationItems.addAll([pin('1', title: 'Look minimal'), pin('2')]);
    final (:auth, :db) = await pumpApp(
      tester,
      overrides: [productImporterProvider.overrideWithValue(importer)],
    );
    expect(auth, isNotNull);
    await openStyle(tester);
    await dismissSnackBar(tester);

    expect(find.text('Look minimal'), findsOne);
    expect(find.text('Do atalho · Pinterest'), findsNWidgets(2));

    await tester.tap(find.byKey(const Key('inspiration-inbox-link-1')));
    await settleUntil(
      tester,
      find.byKey(const Key('inspiration-inbox-1')),
      gone: true,
    );
    final op = (await tester.runAsync(() => styleOperations(db)))!.single;
    expect(op['kind'], 'create_inspiration');
    final data = dataOf(op);
    expect(data['title'], 'Look minimal');
    expect(data['source_url'], 'https://www.pinterest.com/pin/1/');
    expect(data['notes'], 'Blazer e calças largas.');
    expect(importer.discarded, ['1']);

    await tester.tap(find.byKey(const Key('inspiration-inbox-discard-2')));
    await settle(tester);
    expect(find.byKey(const Key('inspiration-inbox-2')), findsNothing);
    expect(importer.discarded, ['1', '2']);
    expect(await styleKinds(tester, db), ['create_inspiration']);
  });

  testWidgets('Pin do atalho com imagem: pergunta, abre a galeria e, ao '
      'guardar, sai da caixa', (tester) async {
    final importer = FakeImporter()
      ..inspirationItems.add(pin('3', title: 'Look'));
    final picker = FakePhotoPicker();
    final (:auth, :db) = await pumpApp(
      tester,
      overrides: [
        productImporterProvider.overrideWithValue(importer),
        photoPickerProvider.overrideWithValue(picker),
        photoStorageProvider.overrideWithValue(null),
      ],
    );
    expect(auth, isNotNull);
    await openStyle(tester);
    await dismissSnackBar(tester);

    await tester.tap(find.byKey(const Key('inspiration-inbox-image-3')));
    await settle(tester);
    expect(find.text('Guardar uma cópia da imagem?'), findsOne);
    expect(find.textContaining('Transferir imagem'), findsOne);

    picker.next.add(testPng(width: 800, height: 1000));
    await tester.tap(find.byKey(const Key('inspiration-image-rights-confirm')));
    await settleUntil(tester, find.byKey(const Key('inspiration-image')));
    expect(picker.sources, [PhotoSource.gallery]);
    expect(importer.discarded, isEmpty, reason: 'ainda não guardou');

    await saveInspiration(tester);
    expect(await styleKinds(tester, db), [
      'create_inspiration',
      'set_inspiration_image',
    ]);
    final data = dataOf(
      (await tester.runAsync(() => styleOperations(db)))!.first,
    );
    expect(data['source_url'], 'https://www.pinterest.com/pin/3/');
    await settle(tester);
    expect(importer.discarded, ['3']);
    expect(find.byKey(const Key('inspiration-inbox-3')), findsNothing);
  });
}
