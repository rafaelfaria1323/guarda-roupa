import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guarda_roupa/features/shopping/application/shopping_providers.dart';
import 'package:guarda_roupa/features/wardrobe/presentation/lens_search_button.dart';

import '../../../support/app_harness.dart';
import '../../../support/fake_photos.dart';
import 'photos_flow_test.dart' show start;

void main() {
  test('endereço do Lens com o link da imagem', () {
    expect(
      lensSearchUri(Uri.parse('https://s.example/a b.jpg?token=x&y=1'))
          .toString(),
      'https://lens.google.com/uploadbyurl'
      '?url=https%3A%2F%2Fs.example%2Fa%2520b.jpg%3Ftoken%3Dx%26y%3D1',
    );
  });

  testWidgets('peça: procurar no Google Lens com um link temporário', (
    tester,
  ) async {
    final storage = FakePhotoStorage();
    final opened = <Uri>[];
    final app = await start(
      tester,
      storage: storage,
      overrides: [
        openLinkProvider.overrideWithValue((uri) async {
          opened.add(uri);
          return true;
        }),
      ],
    );
    app.picker.next.add(testPng(width: 800, height: 1000));
    await tester.tap(find.text('Adicionar peça'));
    await settle(tester);
    await tester.tap(find.byKey(const Key('photo-gallery')));
    await settleUntil(tester, find.byType(Image));
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
    await settleUntil(tester, find.byType(Image));
    await tester.tap(find.byType(Image).first);
    await settle(tester);

    final lens = find.byKey(const Key('lens-search'));
    await tester.scrollUntilVisible(
      lens,
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.ensureVisible(lens);
    await tester.pumpAndSettle();

    // A foto ainda não chegou à nuvem: avisa, sem abrir nada.
    storage.linksFail = true;
    await tester.tap(lens);
    await settleUntil(tester, find.byKey(const Key('lens-error')));
    expect(find.byKey(const Key('lens-open')), findsNothing);
    await tester.tap(find.text('Cancelar'));
    await settle(tester);

    // Com o link: avisa que a imagem vai para a Google e abre o Lens.
    storage.linksFail = false;
    await tester.ensureVisible(
      find.byKey(const Key('lens-search'), skipOffstage: false),
    );
    await tester.pumpAndSettle();
    await tester.tap(lens);
    await settleUntil(tester, find.byKey(const Key('lens-body')));
    expect(find.textContaining('enviada à Google'), findsOneWidget);
    await tester.tap(find.byKey(const Key('lens-open')));
    await settle(tester);
    expect(opened, hasLength(1));
    expect(opened.single.host, 'lens.google.com');
    final image = Uri.parse(opened.single.queryParameters['url']!);
    expect(image.host, 'storage.example');
    expect(image.path, endsWith('/main.jpg'));
    expect(find.byKey(const Key('lens-body')), findsNothing);
  });
}
