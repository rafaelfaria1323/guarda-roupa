import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guarda_roupa/features/wear/application/wear_providers.dart';

import '../../support/app_harness.dart';
import '../wardrobe/domain/fakes.dart';
import '../wardrobe/presentation/wardrobe_flow_test.dart'
    show addGarment, inList, openWardrobe;
import '../wear/wear_flow_test.dart' show openToday, pick, save;
import 'laundry_flow_test.dart' show back;

void main() {
  testWidgets('rotação: data de regresso na ficha e no "Vesti hoje"; '
      'intervalo da peça editável', (tester) async {
    await pumpApp(
      tester,
      overrides: [
        clockProvider.overrideWithValue(
          FixedClock(DateTime.utc(2026, 11, 3, 12)),
        ),
      ],
    );
    await openWardrobe(tester);
    await addGarment(tester, category: 'T-shirt', name: 'Branca');
    await openToday(tester);
    await tester.tap(find.byKey(const Key('wear-today')));
    await settle(tester);
    await tester.tap(pick('Branca'));
    await tester.pump();
    await save(tester);

    // No registo seguinte, aviso informativo (t-shirt: 3 dias).
    await tester.tap(find.byKey(const Key('wear-today')));
    await settleUntil(
      tester,
      find.textContaining('volta à rotação a 6 de novembro de 2026'),
    );
    expect(find.text('Branca'), findsOne);
    await back(tester);

    // Na ficha: data de regresso e intervalo da peça.
    await openWardrobe(tester);
    await tester.tap(inList('Branca'));
    await settle(tester);
    await tester.scrollUntilVisible(
      find.byKey(const Key('garment-details')),
      300,
      scrollable: find
          .descendant(of: find.byType(Form), matching: find.byType(Scrollable))
          .first,
    );
    await settleUntil(tester, find.byKey(const Key('garment-rotation-state')));
    await tester.ensureVisible(find.byKey(const Key('garment-rotation-state')));
    await tester.pumpAndSettle();
    expect(find.text('Volta à rotação a 6 de novembro de 2026.'), findsOne);

    final field = find.byWidgetPredicate(
      (w) =>
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith(
            'garment-rotation-days-',
          ),
    );
    // A snackbar do registo ainda tapa o fundo do ecrã.
    tester
        .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))
        .removeCurrentSnackBar();
    await tester.ensureVisible(field);
    await tester.pumpAndSettle();
    await tester.tap(field);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sem intervalo').last);
    await settleUntil(
      tester,
      find.text('Pode ser usada: já passou o intervalo de rotação.'),
    );
  });
}
