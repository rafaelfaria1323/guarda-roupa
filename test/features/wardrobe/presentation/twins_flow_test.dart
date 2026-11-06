import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guarda_roupa/features/wear/application/wear_providers.dart';

import '../../../support/app_harness.dart';
import '../../wear/wear_flow_test.dart' show chip, openToday, save;
import '../domain/fakes.dart';
import 'wardrobe_flow_test.dart' show inList, openWardrobe;

Finder keyStarting(String prefix) => find.byWidgetPredicate(
  (w) =>
      w.key is ValueKey<String> &&
      (w.key! as ValueKey<String>).value.startsWith(prefix),
);

/// A entrada do grupo no Armário (não o selo ×N nem a folha).
final twinsTile = find.byWidgetPredicate((w) {
  final key = w.key;
  if (key is! ValueKey<String>) return false;
  final v = key.value;
  return v.startsWith('garment-twins-') &&
      !const {'count', 'sheet', 'add'}.contains(v.substring(14));
});

void main() {
  testWidgets('peças iguais: criar três, ver juntas, juntar mais uma e vestir '
      'uma delas', (tester) async {
    await pumpApp(
      tester,
      overrides: [
        clockProvider.overrideWithValue(
          FixedClock(DateTime.utc(2026, 11, 3, 12)),
        ),
      ],
    );
    await openWardrobe(tester);

    // Formulário: "Quantas tens iguais?" cria peças separadas.
    await tester.tap(find.text('Adicionar peça'));
    await settle(tester);
    await tester.tap(find.byKey(const Key('garment-category')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('T-shirt').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('garment-name')), 'Branca');
    await tester.ensureVisible(find.byKey(const Key('garment-units-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('garment-units-more')));
    await tester.tap(find.byKey(const Key('garment-units-more')));
    await tester.pump();
    expect(
      tester.widget<Text>(find.byKey(const Key('garment-units'))).data,
      '3',
    );
    expect(find.textContaining('Ficam peças separadas'), findsOneWidget);
    await tester.tap(find.byKey(const Key('garment-save')));
    await settleUntil(
      tester,
      find.byKey(const Key('garment-save')),
      gone: true,
    );

    // Armário: uma só entrada ×3.
    await settleUntil(tester, find.text('×3'));
    expect(inList('Branca'), findsOneWidget);

    // Folha: cada unidade com o seu estado; juntar mais uma.
    await tester.tap(twinsTile);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('garment-twins-sheet')), findsOneWidget);
    expect(find.text('Branca ×3'), findsOneWidget);
    expect(find.textContaining('Unidade '), findsNWidgets(3));
    expect(find.textContaining('ainda não vestida'), findsNWidgets(3));
    await tester.tap(find.byKey(const Key('garment-twins-add')));
    await settleUntil(tester, find.text('Branca ×4'));
    expect(find.textContaining('Unidade '), findsNWidgets(4));
    await tester.tapAt(const Offset(200, 20));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('garment-twins-sheet')), findsNothing);
    expect(find.text('×4'), findsOneWidget);

    // Vesti hoje: escolher o grupo regista uma só unidade.
    await openToday(tester);
    await tester.tap(find.byKey(const Key('wear-today')));
    await settle(tester);
    expect(find.text('Branca ×4'), findsOneWidget);
    await tester.tap(keyStarting('wear-pick-twins-'));
    await tester.pump();
    expect(find.text('1 peça escolhida'), findsOne);
    await save(tester);
    await tester.ensureVisible(
      find.byWidgetPredicate(
        (w) => w.key.toString().contains('wear-event-'),
        skipOffstage: false,
      ),
    );
    await tester.pumpAndSettle();
    expect(chip('Branca'), findsOne);

    // A usada foi para lavar; as outras três continuam disponíveis.
    await openWardrobe(tester);
    await settleUntil(tester, find.text('3 de 4 disponíveis'));
    await tester.ensureVisible(twinsTile);
    await settle(tester);
    await tester.tap(twinsTile);
    await settleUntil(tester, find.byKey(const Key('garment-twins-sheet')));
    expect(find.textContaining('ainda não vestida'), findsNWidgets(3));
    expect(find.textContaining('vestida a 3 de novembro'), findsOneWidget);
  });
}
