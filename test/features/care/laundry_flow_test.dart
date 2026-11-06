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
  testWidgets('lavagem: ao usar vai sozinha para lavar, "Lavei hoje" '
      'reinicia e devolve-a; aviso por categoria editável', (tester) async {
    final app = await pumpApp(
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
    expect(
      find.text('Utilização registada. Marquei para lavar: Branca.'),
      findsOne,
    );
    Future<String> availability() async =>
        (await tester.runAsync(
              () => app.db.get('SELECT availability FROM garments'),
            ))!['availability']!
            as String;
    expect(await availability(), 'needs_cleaning');

    // T-shirt: suja após cada utilização.
    await openWardrobe(tester);
    await settleUntil(tester, inList('Precisa de limpeza'));

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
    expect(
      find.text('Limpeza registada. Voltou a estar disponível.'),
      findsOne,
    );
    expect(await availability(), 'available');

    // Desfazer a limpeza volta ao aviso e a "Precisa de limpeza".
    await tester.tap(find.text('Desfazer'));
    await settleUntil(
      tester,
      find.byKey(const Key('garment-laundry-recommended')),
    );
    expect(await availability(), 'needs_cleaning');

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

  testWidgets('para lavar já antes do limiar; lavandaria até a ir buscar', (
    tester,
  ) async {
    final app = await pumpApp(
      tester,
      overrides: [
        clockProvider.overrideWithValue(
          FixedClock(DateTime.utc(2026, 11, 3, 12)),
        ),
      ],
    );
    await openWardrobe(tester);
    await addGarment(tester, category: 'Calças', name: 'Pretas');
    Future<String> availability() async =>
        (await tester.runAsync(
              () => app.db.get('SELECT availability FROM garments'),
            ))!['availability']!
            as String;

    // Calças só pedem lavagem às 4 utilizações; uma nódoa marca-as já.
    await openToday(tester);
    await tester.tap(find.byKey(const Key('wear-today')));
    await settle(tester);
    final dirty = find.byWidgetPredicate(
      (w) =>
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('wear-dirty-'),
    );
    expect(dirty, findsNothing);
    await tester.tap(pick('Pretas'));
    await tester.pump();
    await tester.tap(dirty);
    await tester.pump();
    await save(tester);
    expect(
      find.text('Utilização registada. Marquei para lavar: Pretas.'),
      findsOne,
    );
    expect(await availability(), 'needs_cleaning');

    await openWardrobe(tester);
    await openEdit(tester, inList('Pretas'));
    final form = find
        .descendant(of: find.byType(Form), matching: find.byType(Scrollable))
        .first;
    await tester.scrollUntilVisible(
      find.byKey(const Key('garment-details')),
      300,
      scrollable: form,
    );
    await settleUntil(tester, find.byKey(const Key('garment-to-cleaners')));
    await tester.ensureVisible(find.byKey(const Key('garment-to-cleaners')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('garment-laundry-professional')), findsNothing);
    await tester.tap(find.byKey(const Key('garment-to-cleaners')));
    await settleUntil(tester, find.text('Já veio da lavandaria'));
    expect(find.text('Na lavandaria até a ires buscar.'), findsOne);
    expect(await availability(), 'at_cleaners');
    expect(find.byKey(const Key('garment-to-cleaners')), findsNothing);

    await tester.tap(find.byKey(const Key('garment-cleaned')));
    await settleUntil(
      tester,
      find.text('Limpeza registada. Voltou da lavandaria e está disponível.'),
    );
    expect(await availability(), 'available');
    expect(find.text('Sem utilizações desde a última limpeza.'), findsOne);
  });
}
