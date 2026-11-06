import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/app_harness.dart';
import '../wardrobe/presentation/wardrobe_flow_test.dart'
    show inList, openWardrobe;

Future<void> openStyle(WidgetTester tester) async {
  await tester.tap(find.text('Perfil'));
  await settle(tester);
}

/// O SnackBar é do Scaffold exterior e tapa o FAB e o fundo das listas.
Future<void> dismissSnackBar(WidgetTester tester) async {
  tester
      .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))
      .removeCurrentSnackBar();
  await tester.pumpAndSettle();
}

/// Toca numa etiqueta do editor, deslocando a lista até ela existir.
Future<void> tapTag(WidgetTester tester, String key) async {
  final finder = find.byKey(Key(key));
  // Um campo com foco puxa a lista de volta para si; um SnackBar tapa o
  // fundo de uma lista curta.
  FocusManager.instance.primaryFocus?.unfocus();
  await dismissSnackBar(tester);
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  // Ao centro: na borda pode ficar por baixo de um SnackBar.
  await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> saveInspiration(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('inspiration-save')));
  await settleUntil(
    tester,
    find.byKey(const Key('inspiration-save')),
    gone: true,
  );
}

void main() {
  testWidgets('guardar link com etiquetas, corrigir e eliminar; '
      'não cria peças nem inventa análise', (tester) async {
    final (:auth, :db) = await pumpApp(tester);
    expect(auth, isNotNull);

    await openStyle(tester);
    expect(find.text('Ainda não há inspirações.'), findsOne);
    await tester.tap(find.byKey(const Key('inspiration-add')));
    await settle(tester);

    // Vazio: explica, não guarda.
    await tester.tap(find.byKey(const Key('inspiration-save')));
    await tester.pumpAndSettle();
    expect(find.text('Indica um título ou um link.'), findsOne);

    await tester.enterText(
      find.byKey(const Key('inspiration-link')),
      'pinterest.com/pin/123',
    );
    await tester.pump();
    expect(
      find.text('Só fica guardado: a app não abre nem analisa a página.'),
      findsOne,
    );
    await tapTag(tester, 'inspiration-color-navy');
    await tapTag(tester, 'inspiration-color-white');
    await tapTag(tester, 'inspiration-formality-smart_casual');
    await tapTag(tester, 'inspiration-occasion-work_casual');
    await tapTag(tester, 'inspiration-texture-knit');
    await saveInspiration(tester);

    expect(find.text('Inspiração guardada.'), findsOne);
    expect(inList('pinterest.com'), findsOne, reason: 'sem título, o domínio');
    expect(
      find.text('Casual cuidado · Trabalho (smart casual) · Malha'),
      findsOne,
      reason: 'só as etiquetas escolhidas',
    );

    // Corrigir etiquetas e dar um título.
    await tester.tap(inList('pinterest.com'));
    await settle(tester);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('inspiration-link')))
          .controller!
          .text,
      'https://pinterest.com/pin/123',
    );
    await tester.enterText(
      find.byKey(const Key('inspiration-title')),
      'Malhas neutras',
    );
    await tapTag(tester, 'inspiration-formality-relaxed');
    await tapTag(tester, 'inspiration-texture-knit');
    await saveInspiration(tester);
    expect(inList('Malhas neutras'), findsOne);
    expect(
      find.text('pinterest.com\nDescontraído · Trabalho (smart casual)'),
      findsOne,
    );

    // Não é posse.
    await openWardrobe(tester);
    expect(find.text('Ainda não tens peças.'), findsOne);
    final garments = (await tester.runAsync(
      () => db.get('SELECT count(*) AS n FROM garments'),
    ))!;
    expect(garments['n'], 0);

    // Eliminar.
    await openStyle(tester);
    await tester.tap(inList('Malhas neutras'));
    await settle(tester);
    await tester.tap(find.byKey(const Key('inspiration-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('inspiration-delete-confirm')));
    await settleUntil(tester, find.text('Inspiração eliminada.'));
    expect(find.text('Ainda não há inspirações.'), findsOne);
  });
}
