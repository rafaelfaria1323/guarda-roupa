import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guarda_roupa/features/local_ai/application/local_ai_providers.dart';

import '../../support/app_harness.dart';
import '../../support/fake_models.dart';
import '../../support/fake_photos.dart';
import '../wardrobe/presentation/photos_flow_test.dart' show start;
import 'inspiration_flow_test.dart' show dismissSnackBar, openStyle, tapTag;

const _similar = Key('inspiration-similar');

/// Desloca até "Procurar peças parecidas", toca e espera pelo fim (a barra
/// de progresso anima sem parar: nada de pumpAndSettle a meio).
Future<void> findSimilar(WidgetTester tester) async {
  final button = find.byKey(_similar);
  FocusManager.instance.primaryFocus?.unfocus();
  await dismissSnackBar(tester);
  await tester.scrollUntilVisible(
    button,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await Scrollable.ensureVisible(tester.element(button), alignment: 0.5);
  await tester.pump();
  await tester.tap(button);
  await tester.pump();
  await settleUntil(tester, find.byType(LinearProgressIndicator), gone: true);
}

void main() {
  Future<void> addWithPhoto(
    WidgetTester tester,
    FakePhotoPicker picker,
    String name,
    int r,
  ) async {
    picker.next.add(testPng(width: 64, height: 64, r: r));
    await tester.tap(find.text('Adicionar peça'));
    await settle(tester);
    await tester.tap(find.byKey(const Key('garment-category')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('T-shirt').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('garment-name')), name);
    await tester.ensureVisible(find.byKey(const Key('photo-gallery')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('photo-gallery')));
    await settleUntil(tester, find.byType(Image));
    await tester.tap(find.byKey(const Key('garment-save')));
    await settleUntil(
      tester,
      find.byKey(const Key('garment-save')),
      gone: true,
    );
  }

  testWidgets('inspiração com imagem: peças parecidas por ordem, '
      'capas da cache, abrir uma peça', (tester) async {
    final embedder = FakeImageEmbedder();
    final app = await start(
      tester,
      overrides: [imageEmbedderProvider.overrideWithValue(embedder)],
    );
    await addWithPhoto(tester, app.picker, 'Escura', 10);
    await addWithPhoto(tester, app.picker, 'Vermelha', 250);
    await addWithPhoto(tester, app.picker, 'Média', 130);

    await openStyle(tester);
    await dismissSnackBar(tester);
    await tester.tap(find.byKey(const Key('inspiration-add')));
    await settle(tester);
    expect(find.byKey(_similar), findsNothing); // sem imagem

    app.picker.next.add(testPng(width: 200, height: 200, r: 240));
    await tapTag(tester, 'inspiration-image-gallery');
    await tester.tap(find.byKey(const Key('inspiration-image-rights-confirm')));
    await settleUntil(tester, find.byKey(const Key('inspiration-image')));

    await findSimilar(tester);
    expect(embedder.calls, 1 + 3);
    expect(find.textContaining('mais parecidas com a imagem'), findsOne);
    final names = ['Vermelha', 'Média', 'Escura'];
    final ys = [
      for (final n in names)
        tester
            .getTopLeft(
              find.descendant(
                of: find.byWidgetPredicate(
                  (w) =>
                      w is ListTile &&
                      (w.key as ValueKey?)?.value.toString().startsWith(
                            'similar-garment-',
                          ) ==
                          true,
                ),
                matching: find.text(n),
              ),
            )
            .dy,
    ];
    expect(ys, orderedEquals([...ys]..sort()));

    await findSimilar(tester);
    expect(embedder.calls, 4 + 1, reason: 'as capas vêm da cache');

    await tester.tap(find.text('Vermelha'));
    await settle(tester);
    expect(find.byKey(const Key('garment-name')), findsOne);
    expect(find.text('Vermelha'), findsWidgets);
  });

  testWidgets('sem o modelo não há botão', (tester) async {
    final app = await start(tester);
    await openStyle(tester);
    await tester.tap(find.byKey(const Key('inspiration-add')));
    await settle(tester);
    app.picker.next.add(testPng(width: 200, height: 200));
    await tapTag(tester, 'inspiration-image-gallery');
    await tester.tap(find.byKey(const Key('inspiration-image-rights-confirm')));
    await settleUntil(tester, find.byKey(const Key('inspiration-image')));
    expect(find.byKey(_similar), findsNothing);
  });
}
