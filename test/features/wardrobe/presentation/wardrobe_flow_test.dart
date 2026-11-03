import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/app_harness.dart';
import '../../../support/test_database.dart';

Future<void> openWardrobe(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.checkroom_outlined));
  await settle(tester);
}

Future<void> addGarment(
  WidgetTester tester, {
  required String category,
  String? name,
  String? brand,
}) async {
  await tester.tap(find.text('Adicionar peça'));
  await settle(tester);
  await tester.tap(find.byKey(const Key('garment-category')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(category).last);
  await tester.pumpAndSettle();
  if (name != null) {
    await tester.enterText(find.byKey(const Key('garment-name')), name);
  }
  if (brand != null) {
    await tester.enterText(find.byKey(const Key('garment-brand')), brand);
  }
  await tester.tap(find.byKey(const Key('garment-save')));
  await settleUntil(tester, find.byKey(const Key('garment-save')), gone: true);
}

void main() {
  testWidgets('adiciona uma peça, que fica guardada e por sincronizar', (
    tester,
  ) async {
    final app = await pumpApp(tester);
    await openWardrobe(tester);

    await addGarment(
      tester,
      category: 'Calças de ganga',
      name: 'Ganga azul',
      brand: 'Levi’s',
    );

    expect(find.text('Ganga azul'), findsOneWidget);
    expect(find.text('Calças de ganga · Levi’s'), findsOneWidget);
    expect(find.text('Disponível'), findsOneWidget);
    // Guardado localmente, com a operação na fila de envio.
    final pending = (await tester.runAsync(() => pendingOperations(app.db)))!;
    expect(pending.map((op) => op['kind']), ['create']);
    expect(
      find.byTooltip('Só neste dispositivo: sincronização por configurar'),
      findsOneWidget,
    );
  });

  testWidgets('categoria é obrigatória', (tester) async {
    await pumpApp(tester);
    await openWardrobe(tester);

    await tester.tap(find.text('Adicionar peça'));
    await settle(tester);
    await tester.tap(find.byKey(const Key('garment-save')));
    await tester.pumpAndSettle();

    expect(find.text('Escolhe uma categoria.'), findsOneWidget);
  });

  testWidgets('edita, muda a disponibilidade, pesquisa e arquiva', (
    tester,
  ) async {
    await pumpApp(tester);
    await openWardrobe(tester);
    await addGarment(tester, category: 'T-shirt', name: 'Branca');
    await addGarment(tester, category: 'Camisa', name: 'Riscas');

    // Editar o nome.
    await tester.tap(find.text('Branca'));
    await settle(tester);
    await tester.enterText(
      find.byKey(const Key('garment-name')),
      'Branca básica',
    );
    // Disponibilidade aplica-se de imediato.
    await tester.tap(find.text('A lavar'));
    await settleUntil(
      tester,
      find.byWidgetPredicate(
        (w) =>
            w is ChoiceChip &&
            w.selected &&
            (w.label as Text).data == 'A lavar',
      ),
    );
    await tester.tap(find.byKey(const Key('garment-save')));
    await settleUntil(
      tester,
      find.byKey(const Key('garment-save')),
      gone: true,
    );

    expect(find.text('Branca básica'), findsOneWidget);
    expect(find.text('A lavar'), findsOneWidget);

    // Pesquisa sem acentos.
    await tester.enterText(find.byType(TextField), 'BASICA');
    await settle(tester);
    expect(find.text('Branca básica'), findsOneWidget);
    expect(find.text('Riscas'), findsNothing);
    await tester.enterText(find.byType(TextField), '');
    await settle(tester);

    // Arquivar tira da lista; o filtro "Arquivadas" mostra-a.
    await tester.tap(find.text('Riscas'));
    await settle(tester);
    await tester.tap(find.byType(PopupMenuButton<void Function()>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Arquivar'));
    await settleUntil(
      tester,
      find.byKey(const Key('garment-save')),
      gone: true,
    );
    expect(find.text('Riscas'), findsNothing);

    await tester.tap(find.widgetWithText(FilterChip, 'Arquivadas'));
    await settle(tester);
    expect(find.text('Riscas'), findsOneWidget);
    expect(find.text('Camisa · Arquivada'), findsOneWidget);
  });

  testWidgets('duplica uma peça como peça nova', (tester) async {
    await pumpApp(tester);
    await openWardrobe(tester);
    await addGarment(tester, category: 'Polo', name: 'Polo verde');

    await tester.tap(find.text('Polo verde'));
    await settle(tester);
    await tester.tap(find.byType(PopupMenuButton<void Function()>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Duplicar'));
    await settleUntil(tester, find.text('Cópia criada.'));
    // Abre a cópia; ao voltar há duas peças.
    expect(find.text('Editar peça'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await settle(tester);

    expect(find.text('Polo verde'), findsNWidgets(2));
  });

  testWidgets(
    'terminar sessão com pendências bloqueia e recomenda sincronizar',
    (tester) async {
      await pumpApp(tester);
      await openWardrobe(tester);
      await addGarment(tester, category: 'Saia');

      await tester.tap(find.byTooltip('Definições'));
      await settle(tester);
      await tester.tap(find.text('Terminar sessão'));
      await tester.pumpAndSettle();
      expect(
        find.text('Há 1 alteração por enviar. Se saíres agora, perde-se.'),
        findsOneWidget,
      );

      // "Sincronizar primeiro" não sai.
      await tester.tap(find.text('Sincronizar primeiro'));
      await settle(tester);
      expect(find.text('Terminar sessão'), findsOneWidget);

      // Descartar exige segunda confirmação.
      await tester.tap(find.text('Terminar sessão'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sair e descartar'));
      await tester.pumpAndSettle();
      expect(find.text('Descartar alterações?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Sair e descartar'));
      await settleUntil(tester, find.text('Entrar com Google'));

      expect(find.text('Entrar com Google'), findsOneWidget);
    },
  );
}
