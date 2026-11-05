import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:guarda_roupa/features/wear/application/wear_providers.dart';

import '../../support/app_harness.dart';
import '../wardrobe/domain/fakes.dart';
import '../wardrobe/presentation/wardrobe_flow_test.dart'
    show openEdit, closeDetail, addGarment, inList, openWardrobe;
import '../wear/wear_flow_test.dart' show openToday, pick, save;

Future<void> back(WidgetTester tester) async {
  GoRouter.of(tester.element(find.byType(Scaffold).last)).pop();
  await settle(tester);
}

void main() {
  testWidgets('lavagem: aviso após usar, "Lavei hoje" reinicia, sem mudar '
      'a disponibilidade; aviso por categoria editável', (tester) async {
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

    // T-shirt: aviso após cada utilização.
    await openWardrobe(tester);
    await settleUntil(tester, inList('Lavar recomendado'));
    expect(
      find.byKey(const Key('wardrobe-summary')),
      findsOne,
      reason: 'aviso não muda estado',
    );
    expect(find.textContaining('a lavar'), findsNothing);

    await openEdit(tester, inList('Branca'));
    final form = find
        .descendant(of: find.byType(Form), matching: find.byType(Scrollable))
        .first;
    await tester.scrollUntilVisible(
      find.byKey(const Key('garment-details')),
      300,
      scrollable: form,
    );
    await settleUntil(tester, find.byKey(const Key('garment-cleaned')));
    await tester.ensureVisible(find.byKey(const Key('garment-cleaned')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('garment-laundry-recommended')), findsOne);
    expect(
      find.text('1 utilização registada; nenhuma limpeza registada.'),
      findsOne,
    );

    await tester.tap(find.byKey(const Key('garment-cleaned')));
    await settleUntil(
      tester,
      find.byKey(const Key('garment-laundry-recommended')),
      gone: true,
    );
    expect(find.text('Sem utilizações desde a última limpeza.'), findsOne);
    expect(find.text('Limpeza registada.'), findsOne);

    // Desfazer a limpeza volta ao aviso.
    await tester.tap(find.text('Desfazer'));
    await settleUntil(
      tester,
      find.byKey(const Key('garment-laundry-recommended')),
    );

    await tester.tap(find.byKey(const Key('garment-save')));
    await settleUntil(
      tester,
      find.byKey(const Key('garment-save')),
      gone: true,
    );
    await closeDetail(tester);

    // Categoria T-shirt: sem aviso.
    await tester.tap(find.byTooltip('Definições'));
    await settle(tester);
    await tester.tap(find.byKey(const Key('care-settings')));
    await settle(tester);
    final field = find.byWidgetPredicate(
      (w) =>
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith(
            'laundry-category-t_shirt-',
          ),
    );
    await tester.tap(field);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sem aviso').last);
    await settle(tester);
    await back(tester);
    await back(tester);

    await settleUntil(tester, inList('Branca'));
    expect(inList('Lavar recomendado'), findsNothing);
  });
}
