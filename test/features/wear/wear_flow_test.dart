import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guarda_roupa/features/wear/application/wear_providers.dart';

import '../../support/app_harness.dart';
import '../wardrobe/domain/fakes.dart';
import '../wardrobe/presentation/wardrobe_flow_test.dart'
    show openEdit, closeDetail, addGarment, inList, openWardrobe;

Finder keyStarting(String prefix) => find.byWidgetPredicate(
  (w) =>
      w.key is ValueKey<String> &&
      (w.key! as ValueKey<String>).value.startsWith(prefix),
);

Finder chip(String text) =>
    find.descendant(of: keyStarting('wear-event-'), matching: find.text(text));

Finder pick(String text) => find.descendant(
  of: find.byType(CheckboxListTile),
  matching: find.text(text),
);

Future<void> openToday(WidgetTester tester) async {
  await tester.tap(
    find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text('Hoje'),
    ),
  );
  await settle(tester);
  await showWearToday(tester);
}

/// "Vesti hoje" fica por baixo da sugestão do dia.
Future<void> showWearToday(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.byKey(const Key('wear-today')),
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

Future<void> save(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('wear-save')));
  await settleUntil(tester, find.byKey(const Key('wear-save')), gone: true);
}

void main() {
  testWidgets('vesti hoje: registar, ver no histórico, corrigir e desfazer', (
    tester,
  ) async {
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
    await addGarment(tester, category: 'Calças de ganga', name: 'Ganga');

    await openToday(tester);
    expect(find.text('Ainda não registaste o que vestiste hoje.'), findsOne);

    // Registar.
    await tester.tap(find.byKey(const Key('wear-today')));
    await settle(tester);
    expect(find.text('O que vestiste hoje?'), findsOne);
    final saveButton = find.byKey(const Key('wear-save'));
    expect(
      tester.widget<TextButton>(saveButton).onPressed,
      isNull,
      reason: 'sem peças não guarda',
    );
    await tester.tap(pick('Branca'));
    await tester.pump();
    expect(find.text('1 peça escolhida'), findsOne);
    await save(tester);

    // A t-shirt foi para lavar: a sugestão de cima muda e empurra o cartão.
    await tester.ensureVisible(
      find.byWidgetPredicate(
        (w) => w.key.toString().contains('wear-event-'),
        skipOffstage: false,
      ),
    );
    await tester.pumpAndSettle();
    expect(chip('Branca'), findsOne);
    expect(
      find.text('Utilização registada. Marquei para lavar: Branca.'),
      findsOne,
    );

    // Histórico na ficha da peça.
    await openWardrobe(tester);
    await openEdit(tester, inList('Branca'));
    final form = find
        .descendant(of: find.byType(Form), matching: find.byType(Scrollable))
        .first;
    await tester.scrollUntilVisible(
      find.byKey(const Key('garment-details')),
      300,
      scrollable: form,
    );
    // O histórico vem da base local (I/O real): deixar carregar.
    await settleUntil(tester, find.byKey(const Key('garment-wear-count')));
    await tester.ensureVisible(find.byKey(const Key('garment-wear-count')));
    expect(find.text('Usada 1 vez.'), findsOne);
    expect(find.text('• terça-feira, 3 de novembro de 2026'), findsOne);
    await tester.tap(find.byKey(const Key('garment-save')));
    await settleUntil(
      tester,
      find.byKey(const Key('garment-save')),
      gone: true,
    );
    await closeDetail(tester);

    // Corrigir: afinal foi a ganga.
    await openToday(tester);
    await tester.scrollUntilVisible(
      keyStarting('wear-correct-'),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    await Scrollable.ensureVisible(
      tester.element(keyStarting('wear-correct-')),
      alignment: 0.3,
    );
    await tester.pumpAndSettle();
    await tester.tap(keyStarting('wear-correct-'));
    await settle(tester);
    expect(find.text('Corrigir utilização'), findsOne);
    await tester.tap(pick('Branca'));
    await tester.tap(pick('Ganga'));
    await tester.pump();
    await save(tester);
    expect(chip('Ganga'), findsOne);
    expect(chip('Branca'), findsNothing);

    // Desfazer.
    await tester.scrollUntilVisible(
      keyStarting('wear-undo-'),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    await Scrollable.ensureVisible(
      tester.element(keyStarting('wear-undo-')),
      alignment: 0.3,
    );
    await tester.pumpAndSettle();
    await tester.tap(keyStarting('wear-undo-'));
    await settleUntil(
      tester,
      find.text('Ainda não registaste o que vestiste hoje.'),
    );
    expect(find.text('Ainda não registaste o que vestiste hoje.'), findsOne);
    expect(find.text('Utilização desfeita.'), findsOne);
  });
}
