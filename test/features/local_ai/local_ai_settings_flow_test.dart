import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guarda_roupa/features/local_ai/application/local_ai_providers.dart';

import '../../support/app_harness.dart';
import '../../support/fake_models.dart';

void main() {
  Future<FakeModelStore> open(WidgetTester tester) async {
    final store = FakeModelStore();
    await pumpApp(
      tester,
      overrides: [modelStoreProvider.overrideWithValue(store)],
    );
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
    expect(
      find.text('Desligada: as sugestões usam o método simples'),
      findsOneWidget,
    );
    await tester.tap(tile);
    await settle(tester);
    return store;
  }

  const download = Key('local-model-download-u2netp');

  testWidgets('descarrega só a pedido, mostra o progresso e remove', (
    tester,
  ) async {
    final store = await open(tester);
    expect(
      find.textContaining('U²-Netp · 4,6 MB · licença Apache-2.0'),
      findsOneWidget,
    );
    expect(store.pending, isNull); // nada se descarrega sem pedir

    await tester.tap(find.byKey(download));
    await tester.pump();
    store.pending!.add(0.5);
    await tester.pump();
    expect(find.text('A descarregar… 50 %'), findsOneWidget);

    await store.pending!.close();
    await tester.pump();
    await tester.pump();
    expect(find.text('Pronto neste dispositivo'), findsOneWidget);
    expect(store.ready, {'u2netp'});

    await tester.tap(find.byKey(const Key('local-model-remove-u2netp')));
    await tester.pump();
    await tester.pump();
    expect(store.ready, isEmpty);
    expect(find.byKey(download), findsOneWidget);
  });

  testWidgets('descarga interrompida: avisa e deixa tentar de novo', (
    tester,
  ) async {
    final store = await open(tester);
    await tester.tap(find.byKey(download));
    await tester.pump();
    store.pending!.addError(StateError('sem rede'));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('local-model-failed-u2netp')), findsOneWidget);
    expect(store.ready, isEmpty);
    expect(find.byKey(download), findsOneWidget);
  });
}
