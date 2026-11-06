import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guarda_roupa/features/local_ai/application/local_ai_providers.dart';

import '../../../support/app_harness.dart';
import '../../../support/fake_models.dart';
import '../../../support/fake_photos.dart';
import '../../../support/mask_photos.dart';
import 'photos_flow_test.dart' show start, openGarment;

final _photo = find.byType(Image);

// A lista do formulário: a última (a do guarda-roupa fica por baixo) e não
// o Scrollable de um campo de texto.
// Fica ao centro, longe da snackbar.
/// [delta] negativo sobe (as fotos ficam no topo do formulário).
Future<void> scrollTo(
  WidgetTester tester,
  Finder finder, {
  double delta = 200,
}) async {
  await tester.scrollUntilVisible(
    finder,
    delta,
    scrollable: find
        .descendant(
          of: find.byType(ListView).last,
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
  await tester.pump();
}

void main() {
  testWidgets('peça nova: sugere pela foto, desfaz, confirma e guarda', (
    tester,
  ) async {
    final app = await start(tester);
    app.picker.next.add(testPng(width: 400, height: 300)); // vermelho

    await tester.tap(find.text('Adicionar peça'));
    await settle(tester);
    await tester.tap(find.byKey(const Key('garment-category')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Camisa').last);
    await tester.pumpAndSettle();
    await scrollTo(tester, find.byKey(const Key('color-white')));
    // Sem foto não há o que sugerir.
    expect(find.byKey(const Key('colors-from-photo')), findsNothing);

    await scrollTo(tester, find.byKey(const Key('photo-gallery')), delta: -200);
    await tester.tap(find.byKey(const Key('photo-gallery')));
    await settleUntil(tester, _photo);

    await scrollTo(tester, find.byKey(const Key('colors-from-photo')));
    await tester.tap(find.byKey(const Key('colors-from-photo')));
    await tester.pump();
    expect(
      find.text('Cores sugeridas pela foto: confirma ou ajusta.'),
      findsOneWidget,
    );
    expect(find.text('Vermelho · sugerida'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 500)); // entra a snackbar
    await tester.tap(find.text('Desfazer'));
    await tester.pump();
    expect(find.text('Vermelho · sugerida'), findsNothing);

    await tester.tap(find.byKey(const Key('colors-from-photo')));
    await tester.pump();
    await scrollTo(tester, find.byKey(const Key('colors-confirm')));
    await tester.tap(find.byKey(const Key('colors-confirm')));
    await tester.pump();
    expect(find.text('Vermelho · sugerida'), findsNothing);
    expect(find.byKey(const Key('colors-confirm')), findsNothing);

    await tester.tap(find.byKey(const Key('garment-save')));
    await settleUntil(
      tester,
      find.byKey(const Key('garment-save')),
      gone: true,
    );

    final row = (await tester.runAsync(
      () => app.db.get('SELECT colors FROM garments'),
    ))!;
    expect(jsonDecode(row['colors'] as String), [
      {'rgb': 0xC0392B, 'proportion': 1.0, 'confirmed': true},
    ]);
  });

  testWidgets('peça existente: sugestão fica por confirmar ao guardar', (
    tester,
  ) async {
    final app = await start(tester);
    await tester.tap(find.text('Adicionar peça'));
    await settle(tester);
    await tester.tap(find.byKey(const Key('garment-category')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('T-shirt').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('garment-name')), 'Branca');
    await tester.tap(find.byKey(const Key('garment-save')));
    await settleUntil(
      tester,
      find.byKey(const Key('garment-save')),
      gone: true,
    );
    await openGarment(tester, 'Branca');

    app.picker.next.add(testPng(r: 250));
    await tester.tap(find.byKey(const Key('photo-camera')));
    await settleUntil(tester, _photo);

    await scrollTo(tester, find.byKey(const Key('colors-from-photo')));
    await tester.tap(find.byKey(const Key('colors-from-photo')));
    await settle(tester);
    expect(find.textContaining('· sugerida'), findsOneWidget);

    await tester.tap(find.byKey(const Key('garment-save')));
    await settleUntil(
      tester,
      find.byKey(const Key('garment-save')),
      gone: true,
    );
    final row = (await tester.runAsync(
      () => app.db.get('SELECT colors FROM garments'),
    ))!;
    final colors = (jsonDecode(row['colors'] as String) as List)
        .cast<Map<String, Object?>>();
    expect(colors.single['confirmed'], false);
  });

  testWidgets('com o modelo de recorte, o fundo não entra nas cores', (
    tester,
  ) async {
    final remover = FakeBackgroundRemover(rectMask());
    final app = await start(
      tester,
      overrides: [backgroundRemoverProvider.overrideWithValue(remover)],
    );
    app.picker.next.add(gradientPhoto());

    await tester.tap(find.text('Adicionar peça'));
    await settle(tester);
    await scrollTo(tester, find.byKey(const Key('photo-gallery')), delta: -200);
    await tester.tap(find.byKey(const Key('photo-gallery')));
    await settleUntil(tester, _photo);

    await scrollTo(tester, find.byKey(const Key('colors-from-photo')));
    await tester.tap(find.byKey(const Key('colors-from-photo')));
    await settle(tester);
    expect(remover.calls, 1);
    expect(
      find.text('Cores sugeridas sem o fundo da foto: confirma ou ajusta.'),
      findsOneWidget,
    );
    expect(find.text('Vermelho · sugerida'), findsOneWidget);
    expect(find.textContaining('· sugerida'), findsOneWidget);
  });

  testWidgets('se o recorte falhar, sugere na mesma pela borda', (
    tester,
  ) async {
    final remover = FakeBackgroundRemover(null)..failWith = StateError('x');
    final app = await start(
      tester,
      overrides: [backgroundRemoverProvider.overrideWithValue(remover)],
    );
    app.picker.next.add(testPng(width: 400, height: 300));

    await tester.tap(find.text('Adicionar peça'));
    await settle(tester);
    await scrollTo(tester, find.byKey(const Key('photo-gallery')), delta: -200);
    await tester.tap(find.byKey(const Key('photo-gallery')));
    await settleUntil(tester, _photo);

    await scrollTo(tester, find.byKey(const Key('colors-from-photo')));
    await tester.tap(find.byKey(const Key('colors-from-photo')));
    await settle(tester);
    expect(
      find.text('Cores sugeridas pela foto: confirma ou ajusta.'),
      findsOneWidget,
    );
    expect(find.text('Vermelho · sugerida'), findsOneWidget);
  });
}
