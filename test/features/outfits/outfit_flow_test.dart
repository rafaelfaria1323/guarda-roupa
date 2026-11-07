import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guarda_roupa/features/wardrobe/data/powersync_wardrobe_repository.dart';
import 'package:guarda_roupa/features/wardrobe/domain/availability.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment_category.dart';
import 'package:guarda_roupa/features/wear/application/wear_providers.dart';
import 'package:powersync/powersync.dart';

import '../../support/app_harness.dart';
import '../wardrobe/domain/fakes.dart';
import '../wardrobe/presentation/wardrobe_flow_test.dart'
    show inList, openWardrobe;
import '../wear/wear_flow_test.dart' show openToday, save;

Future<void> openOutfits(WidgetTester tester) async {
  await tester.tap(find.text('Conjuntos'));
  await settle(tester);
}

Future<String> idOf(
  WidgetTester tester,
  PowerSyncDatabase db,
  String name,
) async =>
    (await tester.runAsync(
          () => db.get('SELECT id FROM garments WHERE name = ?', [name]),
        ))!['id']!
        as String;

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Finder addCard(String name) => find.descendant(
  of: find.byWidgetPredicate(
    (w) =>
        w.key is ValueKey<String> &&
        (w.key! as ValueKey<String>).value.startsWith('outfit-add-'),
  ),
  matching: find.text(name),
);

Future<void> saveOutfit(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('outfit-save')));
  await settleUntil(tester, find.byKey(const Key('outfit-save')), gone: true);
}

void main() {
  testWidgets('criar t-shirt + calças + ténis sem casaco, avisar indisponível, '
      'usar em "Vesti hoje" e editar sem mudar a utilização', (tester) async {
    final (:auth, :db) = await pumpApp(
      tester,
      overrides: [
        clockProvider.overrideWithValue(
          FixedClock(DateTime.utc(2026, 11, 3, 12)),
        ),
      ],
    );
    expect(auth, isNotNull);
    final wardrobe = PowerSyncWardrobeRepository(db: db, ownerId: 'user-a');
    await tester.runAsync(() async {
      for (final (category, name) in [
        (GarmentCategory.tShirt, 'Branca'),
        (GarmentCategory.trousers, 'Pretas'),
        (GarmentCategory.sneakers, 'Brancos'),
        (GarmentCategory.coat, 'Inverno'),
      ]) {
        await wardrobe.addGarment(GarmentDraft(category: category, name: name));
      }
    });
    final pretas = await idOf(tester, db, 'Pretas');

    // Criar.
    await openOutfits(tester);
    expect(find.text('Ainda não há conjuntos guardados.'), findsOne);
    await tester.tap(find.byKey(const Key('outfit-add')));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('outfit-name')), 'Sexta');
    await tester.tap(find.byKey(const Key('outfit-occasion-casual')));
    await tester.tap(find.byKey(const Key('outfit-occasion-evening')));
    await tester.pump();
    expect(find.byKey(const Key('outfit-group-all')), findsOne);
    for (final name in ['Branca', 'Pretas']) {
      await tapVisible(tester, addCard(name));
    }
    expect(
      tester.widget<Text>(find.byKey(const Key('outfit-count'))).data,
      '2 peças',
    );
    expect(find.text('Tudo disponível'), findsOne);
    expect(find.text('Falta: calçado. Podes guardar na mesma.'), findsOne);
    // Filtrar por grupo: só o calçado fica na bandeja.
    await tapVisible(tester, find.byKey(const Key('outfit-group-footwear')));
    expect(addCard('Inverno'), findsNothing);
    await tapVisible(tester, addCard('Brancos'));
    expect(find.text('Conjunto completo.'), findsOne, reason: 'sem casaco');
    await saveOutfit(tester);

    expect(find.text('Conjunto guardado.'), findsOne);
    expect(find.text('Sexta'), findsOne);
    expect(find.text('3 peças'), findsOne);
    expect(find.text('Casual · Noite / saída'), findsOne);
    expect(find.text('Ainda não usado'), findsOne);
    expect(find.text('1 conjunto guardado'), findsOne);
    expect(find.text('Todos (1)'), findsOne);
    expect(find.text('Casual (1)'), findsOne);

    // Indisponível: aviso, sem mudar o conjunto.
    await tester.runAsync(
      () => PowerSyncWardrobeRepository(
        db: db,
        ownerId: 'user-a',
      ).setAvailability(GarmentId(pretas), Availability.washing),
    );
    await settleUntil(tester, find.textContaining('1 peça não está'));
    await tester.tap(find.text('Sexta'));
    await settle(tester);
    expect(find.byKey(Key('outfit-warning-$pretas')), findsOne);
    expect(
      tester.widget<Text>(find.byKey(Key('outfit-warning-$pretas'))).data,
      'A lavar',
    );
    expect(find.text('1 peça não está disponível'), findsOne);

    // Trocar o papel e tirar a peça indisponível.
    await tapVisible(tester, find.byKey(Key('outfit-remove-$pretas')));
    expect(find.textContaining('Falta: parte de baixo'), findsOne);
    await saveOutfit(tester);

    // Usar em "Vesti hoje".
    await openToday(tester);
    tester
        .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger).first)
        .clearSnackBars();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('wear-today')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('wear-today')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('wear-from-outfit')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text('Sexta'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('2 peças escolhidas'), findsOne);
    await save(tester);
    // A t-shirt foi para lavar sozinha; o aviso (mais alto) sai da frente.
    expect(find.textContaining('Marquei para lavar: Branca'), findsOne);
    tester
        .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))
        .removeCurrentSnackBar();
    await tester.pumpAndSettle();

    // Editar o conjunto não muda a utilização registada.
    await openOutfits(tester);
    await tester.tap(find.text('Sexta'));
    await settle(tester);
    await tapVisible(tester, addCard('Pretas'));
    await saveOutfit(tester);
    final wear = (await tester.runAsync(
      () => db.get('SELECT garment_ids FROM wear_events'),
    ))!;
    expect(jsonDecode(wear['garment_ids']! as String), hasLength(2));
    expect(find.textContaining('4 peças'), findsNothing);
    expect(find.textContaining('3 peças'), findsOne);

    // Eliminar.
    await tester.tap(find.text('Sexta'));
    await settle(tester);
    await tester.tap(find.byKey(const Key('outfit-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('outfit-delete-confirm')));
    await settleUntil(tester, find.text('Conjunto eliminado.'));
    expect(find.text('Ainda não há conjuntos guardados.'), findsOne);
    await openWardrobe(tester);
    expect(inList('Pretas'), findsOne, reason: 'as peças ficam');
  });
}
