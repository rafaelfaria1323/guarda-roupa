import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/app_harness.dart';
import '../wardrobe/presentation/wardrobe_flow_test.dart' show inList;
import 'inspiration_flow_test.dart'
    show dismissSnackBar, openStyle, saveInspiration, tapTag;

Future<void> openPreferences(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('style-segment-preferences')));
  await settle(tester);
}

Future<void> savePreference(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('preference-save')));
  await settleUntil(
    tester,
    find.byKey(const Key('preference-save')),
    gone: true,
  );
}

Future<void> newPreference(
  WidgetTester tester, {
  required String stance,
  required String subject,
  required String value,
  String? occasion,
}) async {
  await dismissSnackBar(tester);
  await tester.tap(find.byKey(const Key('preference-add')));
  await settle(tester);
  await tapTag(tester, 'preference-stance-$stance');
  await tapTag(tester, 'preference-subject-$subject');
  await tapTag(tester, 'preference-value-$value');
  if (occasion != null) await tapTag(tester, 'preference-occasion-$occasion');
}

void main() {
  testWidgets('criar, corrigir, repetir e eliminar preferências; '
      'criar a partir de uma inspiração só com confirmação', (tester) async {
    final (:auth, :db) = await pumpApp(tester);
    expect(auth, isNotNull);

    await openStyle(tester);
    await openPreferences(tester);
    expect(find.text('Ainda não há preferências.'), findsOne);

    // Sem valor não guarda.
    await tester.tap(find.byKey(const Key('preference-add')));
    await settle(tester);
    expect(
      tester
          .widget<TextButton>(find.byKey(const Key('preference-save')))
          .onPressed,
      isNull,
    );
    await tester.tap(find.byType(BackButton));
    await settle(tester);

    await newPreference(
      tester,
      stance: 'avoid',
      subject: 'pattern',
      value: 'stripes',
      occasion: 'evening',
    );
    await savePreference(tester);
    expect(find.text('Preferência guardada.'), findsOne);
    expect(inList('Evito: Riscas'), findsOne);
    expect(find.text('Padrão · Noite / saída'), findsOne);

    // Repetida no mesmo contexto: explica e não guarda.
    await newPreference(
      tester,
      stance: 'like',
      subject: 'pattern',
      value: 'stripes',
      occasion: 'evening',
    );
    await tester.tap(find.byKey(const Key('preference-save')));
    await settleUntil(
      tester,
      find.text('Já tens uma preferência para isto, no mesmo contexto.'),
    );
    await tester.tap(find.byType(BackButton));
    await settle(tester);

    // Corrigir: o assunto fica fixo.
    await tester.tap(inList('Evito: Riscas'));
    await settle(tester);
    expect(
      tester
          .widget<ChoiceChip>(find.byKey(const Key('preference-subject-color')))
          .onSelected,
      isNull,
    );
    await tapTag(tester, 'preference-stance-like');
    await tapTag(tester, 'preference-occasion-evening');
    await savePreference(tester);
    expect(inList('Gosto: Riscas'), findsOne);
    expect(find.text('Padrão · Sempre'), findsOne);

    // A partir de uma inspiração: escolher quais.
    await tester.tap(find.byKey(const Key('style-segment-inspirations')));
    await settle(tester);
    await dismissSnackBar(tester);
    await tester.tap(find.byKey(const Key('inspiration-add')));
    await settle(tester);
    await tester.enterText(
      find.byKey(const Key('inspiration-title')),
      'Neutros',
    );
    await tapTag(tester, 'inspiration-color-navy');
    await tapTag(tester, 'inspiration-texture-knit');
    await saveInspiration(tester);
    await tester.tap(inList('Neutros'));
    await settle(tester);
    await tapTag(tester, 'inspiration-make-preferences');
    expect(find.text('Gosto: Azul-marinho'), findsOne);
    expect(find.text('Gosto: Malha'), findsOne);
    await tester.tap(find.byKey(const Key('make-preference-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('make-preferences-confirm')));
    await settleUntil(tester, find.text('1 preferência criada.'));
    await tester.tap(find.byType(BackButton));
    await settle(tester);

    await openPreferences(tester);
    expect(inList('Gosto: Azul-marinho'), findsOne);
    expect(find.text('Cor · Sempre\nDa inspiração «Neutros»'), findsOne);
    expect(find.text('Gosto: Malha'), findsNothing);

    // Eliminar.
    await tester.tap(inList('Gosto: Riscas'));
    await settle(tester);
    await tester.tap(find.byKey(const Key('preference-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('preference-delete-confirm')));
    await settleUntil(tester, find.text('Preferência eliminada.'));
    expect(inList('Gosto: Riscas'), findsNothing);

    final garments = (await tester.runAsync(
      () => db.get('SELECT count(*) AS n FROM garments'),
    ))!;
    expect(garments['n'], 0, reason: 'preferências não são peças');
  });
}
