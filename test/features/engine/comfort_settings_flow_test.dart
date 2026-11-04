import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guarda_roupa/features/engine/data/comfort_store.dart';
import 'package:guarda_roupa/features/engine/domain/comfort.dart';

import '../../support/app_harness.dart';

void main() {
  Future<void> openComfort(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Definições'));
    await settle(tester);
    expect(
      find.text('Calor ≥ 22 °C · frio < 14 °C · vento ≥ 30 km/h'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('comfort-settings')));
    await settle(tester);
  }

  String valueOf(WidgetTester tester, String id) =>
      tester.widget<Text>(find.byKey(Key('comfort-$id-value'))).data!;

  bool enabled(WidgetTester tester, String key) =>
      switch (tester.widget(find.byKey(Key(key)))) {
        IconButton(:final onPressed) => onPressed != null,
        ButtonStyleButton(:final onPressed) => onPressed != null,
        _ => throw StateError('não é um botão: $key'),
      };

  testWidgets('altera, guarda e repõe os limites', (tester) async {
    final (:auth, :db) = await pumpApp(tester);
    await openComfort(tester);

    expect(valueOf(tester, 'hot'), '22 °C');
    expect(enabled(tester, 'comfort-save'), isFalse);
    expect(enabled(tester, 'comfort-reset'), isFalse);

    await tester.tap(find.byKey(const Key('comfort-hot-plus')));
    await tester.tap(find.byKey(const Key('comfort-wind-plus')));
    await tester.pump();
    expect(valueOf(tester, 'hot'), '23 °C');
    expect(valueOf(tester, 'wind'), '35 km/h');
    expect(
      find.text(
        'Entre 14 e 23 °C: peças médias ou leves, com camada opcional.',
      ),
      findsOneWidget,
    );
    expect(enabled(tester, 'comfort-save'), isTrue);

    await tester.tap(find.byKey(const Key('comfort-save')));
    await settle(tester);
    expect(find.text('Limites de conforto guardados.'), findsOneWidget);
    expect(enabled(tester, 'comfort-save'), isFalse);

    final stored = await tester.runAsync(() => ComfortStore(db).get());
    expect(stored, const ComfortThresholds(hotFromC: 23, windyFromKmh: 35));

    await tester.tap(find.byType(BackButton));
    await settle(tester);
    expect(
      find.text('Calor ≥ 23 °C · frio < 14 °C · vento ≥ 35 km/h'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('comfort-settings')));
    await settle(tester);
    expect(valueOf(tester, 'hot'), '23 °C');
    await tester.tap(find.byKey(const Key('comfort-reset')));
    await tester.pump();
    expect(valueOf(tester, 'hot'), '22 °C');
    expect(valueOf(tester, 'wind'), '30 km/h');
    await tester.tap(find.byKey(const Key('comfort-save')));
    await settle(tester);
    final reset = await tester.runAsync(() => ComfortStore(db).get());
    expect(reset, const ComfortThresholds());
  });

  testWidgets('o frio não chega ao calor', (tester) async {
    await pumpApp(tester);
    await openComfort(tester);

    // Calor 22 → 15 (mínimo) e frio 14 → só desce.
    for (var i = 0; i < 7; i++) {
      await tester.tap(find.byKey(const Key('comfort-hot-minus')));
      await tester.pump();
    }
    expect(valueOf(tester, 'hot'), '15 °C');
    expect(enabled(tester, 'comfort-hot-minus'), isFalse);
    expect(enabled(tester, 'comfort-cold-plus'), isFalse);
    await tester.tap(find.byKey(const Key('comfort-hot-minus')));
    await tester.pump();
    expect(valueOf(tester, 'hot'), '15 °C');
  });
}
