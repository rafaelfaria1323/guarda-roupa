import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/app_harness.dart';
import '../../../support/test_database.dart';

/// Texto dentro de um item da lista (os filtros repetem as etiquetas).
/// Um texto numa linha de lista ou numa peça do Armário.
Finder inList(String text) => find.descendant(
  of: find.byWidgetPredicate(
    (w) =>
        w is ListTile ||
        (w.key is ValueKey<String> &&
            ((w.key! as ValueKey<String>).value.startsWith('garment-tile-') ||
                (w.key! as ValueKey<String>).value.startsWith(
                  'garment-twins-',
                ))),
  ),
  matching: find.text(text),
);

/// Abre a ficha de uma peça (modo de ver) e passa a editar.
Future<void> openEdit(WidgetTester tester, Finder garment) async {
  await tester.tap(garment);
  await settle(tester);
  await tester.tap(find.byKey(const Key('garment-edit')));
  await settle(tester);
}

/// Sai da ficha da peça (modo de ver) de volta ao Armário.
Future<void> closeDetail(WidgetTester tester) async {
  await tester.tap(find.byType(BackButton));
  await settle(tester);
}

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
    // Disponível é o normal: a peça não mostra estado.
    expect(inList('Disponível'), findsNothing);
    expect(find.text('1 peça'), findsOneWidget);
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
    await openEdit(tester, find.text('Branca'));
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
    await closeDetail(tester);

    expect(find.text('Branca básica'), findsOneWidget);
    expect(inList('A lavar'), findsOneWidget);

    // Pesquisa sem acentos.
    await tester.enterText(find.byType(TextField), 'BASICA');
    await settle(tester);
    expect(find.text('Branca básica'), findsOneWidget);
    expect(find.text('Riscas'), findsNothing);
    await tester.enterText(find.byType(TextField), '');
    await settle(tester);

    // Arquivar tira da lista; o filtro "Arquivadas" mostra-a.
    await openEdit(tester, find.text('Riscas'));
    await tester.tap(find.byType(PopupMenuButton<void Function()>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Arquivar'));
    await settleUntil(
      tester,
      find.byKey(const Key('garment-save')),
      gone: true,
    );
    expect(find.text('Riscas'), findsNothing);

    await tester.ensureVisible(find.byKey(const Key('filter-archived')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('filter-archived')));
    await settle(tester);
    expect(find.text('Riscas'), findsOneWidget);
    expect(inList('Arquivada'), findsOneWidget);
  });

  testWidgets('duplica uma peça como peça nova', (tester) async {
    await pumpApp(tester);
    await openWardrobe(tester);
    await addGarment(tester, category: 'Polo', name: 'Polo verde');

    await openEdit(tester, find.text('Polo verde'));
    await tester.tap(find.byType(PopupMenuButton<void Function()>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Duplicar'));
    await settleUntil(
      tester,
      find.text('Cópia criada, com as mesmas fotografias.'),
    );
    // Abre a cópia; ao voltar há duas peças.
    expect(find.text('Editar peça'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await settle(tester);
    await closeDetail(tester);

    // Duas peças iguais: juntas no Armário, cada uma com a sua ficha.
    expect(inList('Polo verde'), findsOneWidget);
    expect(find.byKey(const Key('garment-twins-count')), findsOneWidget);
    expect(find.text('×2'), findsOneWidget);
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

  testWidgets('filtra por grupo e disponibilidade e limpa filtros', (
    tester,
  ) async {
    await pumpApp(tester);
    await openWardrobe(tester);
    await addGarment(tester, category: 'T-shirt', name: 'Branca');
    await addGarment(tester, category: 'Calções', name: 'Brancos');

    await tester.tap(find.byKey(const Key('filter-group-bottom')));
    await settle(tester);
    expect(inList('Brancos'), findsOneWidget);
    expect(inList('Branca'), findsNothing);

    await tester.ensureVisible(
      find.byKey(const Key('filter-availability-washing')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('filter-availability-washing')));
    await settle(tester);
    expect(find.text('Nenhuma peça corresponde à pesquisa.'), findsOneWidget);

    await tester.ensureVisible(find.text('Limpar filtros'));
    await tester.tap(find.text('Limpar filtros'));
    await settle(tester);
    expect(inList('Branca'), findsOneWidget);
    expect(inList('Brancos'), findsOneWidget);
    expect(find.text('Limpar filtros'), findsNothing);
  });

  testWidgets('escolhe cores e proporções; acima de 100% não guarda', (
    tester,
  ) async {
    final app = await pumpApp(tester);
    await openWardrobe(tester);
    await tester.tap(find.text('Adicionar peça'));
    await settle(tester);
    await tester.tap(find.byKey(const Key('garment-category')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Camisa').last);
    await tester.pumpAndSettle();

    Future<void> tapKey(String key) async {
      // O formulário é uma lista preguiçosa: pode ainda não estar construída.
      await tester.scrollUntilVisible(
        find.byKey(Key(key)),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.byKey(Key(key)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key(key)));
      await tester.pumpAndSettle();
    }

    await tapKey('color-white'); // fica com 100%
    expect(find.text('Por atribuir: 0%'), findsOneWidget);
    await tapKey('color-navy'); // não cabe: 10%, acima do total
    expect(find.text('As proporções somam mais de 100%.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('garment-save')));
    await settle(tester);
    expect(
      find.byKey(const Key('garment-save')),
      findsOneWidget,
      reason: 'fica',
    );

    // Branco para 70%: o slider vai de 10 a 100 em 9 passos.
    final slider = find.byKey(const Key('color-percent-0'));
    await tester.ensureVisible(slider);
    await tester.pumpAndSettle();
    final box = tester.getRect(slider);
    // Área útil do Slider tem margens; arrasta para a esquerda até ~70%.
    await tester.drag(slider, Offset(-box.width * 0.36, 0));
    await tester.pumpAndSettle();
    expect(find.text('As proporções somam mais de 100%.'), findsNothing);

    await tester.tap(find.byKey(const Key('garment-save')));
    await settleUntil(
      tester,
      find.byKey(const Key('garment-save')),
      gone: true,
    );
    final op = (await tester.runAsync(() => pendingOperations(app.db)))!.single;
    final colors = [
      for (final c
          in (jsonDecode(op['data']! as String) as Map)['colors'] as List)
        c as Map<String, Object?>,
    ];
    expect(colors.map((c) => c['rgb']), [0xFFFFFF, 0x1F2A44]);
    expect(colors.every((c) => c['confirmed'] == true), isTrue);
    final sum = colors.fold<num>(0, (s, c) => s + (c['proportion']! as num));
    expect(sum, lessThanOrEqualTo(1.0 + 1e-9));
  });

  testWidgets('eliminar pede confirmação e tira a peça', (tester) async {
    final app = await pumpApp(tester);
    await openWardrobe(tester);
    await addGarment(tester, category: 'Saia', name: 'Plissada');
    await openEdit(tester, find.text('Plissada'));

    await tester.tap(find.byType(PopupMenuButton<void Function()>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Eliminar'));
    await tester.pumpAndSettle();
    expect(find.text('Eliminar esta peça?'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('garment-save')), findsOneWidget);

    await tester.tap(find.byType(PopupMenuButton<void Function()>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Eliminar'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('garment-delete-confirm')));
    await settleUntil(
      tester,
      find.byKey(const Key('garment-save')),
      gone: true,
    );

    expect(inList('Plissada'), findsNothing);
    final kinds = [
      for (final op in (await tester.runAsync(
        () => pendingOperations(app.db),
      ))!)
        op['kind'],
    ];
    expect(kinds, ['create', 'delete']);
  });

  testWidgets('detalhes opcionais: escolhe, desfaz e filtra por ocasião', (
    tester,
  ) async {
    final app = await pumpApp(tester);
    await openWardrobe(tester);
    await addGarment(tester, category: 'T-shirt', name: 'Branca');
    await tester.tap(find.text('Adicionar peça'));
    await settle(tester);
    await tester.tap(find.byKey(const Key('garment-category')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Camisola').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('garment-name')), 'Grossa');

    Future<void> tapKey(String key) async {
      // O formulário é uma lista preguiçosa: pode ainda não estar construída.
      await tester.scrollUntilVisible(
        find.byKey(Key(key)),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.byKey(Key(key)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key(key)));
      await tester.pumpAndSettle();
    }

    await tapKey('garment-details');
    await tapKey('pattern-stripes');
    await tapKey('pattern-checks');
    await tapKey('pattern-checks'); // desfaz: fica por saber
    await tapKey('warmth-warm');
    await tapKey('rain-no');
    await tapKey('formality-dressy');
    await tapKey('fit-relaxed');
    await tapKey('length-cropped');
    await tapKey('occasion-evening');
    await tapKey('wash-machine_40');
    await tapKey('tumble-dry-no');
    await tester.ensureVisible(find.byKey(const Key('garment-material')));
    await tester.enterText(find.byKey(const Key('garment-material')), 'Lã');
    await tester.tap(find.byKey(const Key('garment-save')));
    await settleUntil(
      tester,
      find.byKey(const Key('garment-save')),
      gone: true,
    );

    final op = (await tester.runAsync(() => pendingOperations(app.db)))!.last;
    final data = jsonDecode(op['data']! as String) as Map<String, Object?>;
    expect(data['pattern'], isNull);
    expect(data['warmth'], 'warm');
    expect(data['rain_ok'], false);
    expect(data['wind_ok'], isNull);
    expect(data['formality'], 'dressy');
    expect(data['fit'], 'relaxed');
    expect(data['length'], 'cropped');
    expect(data['occasions'], ['evening']);
    expect(data['wash'], 'machine_40');
    expect(data['tumble_dry'], false);
    expect(data['material'], 'Lã');

    await tester.ensureVisible(
      find.byKey(const Key('filter-occasion-evening')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('filter-occasion-evening')));
    await settle(tester);
    expect(inList('Grossa'), findsOneWidget);
    expect(inList('Branca'), findsNothing);

    // Ao reabrir, os detalhes vêm abertos e preenchidos.
    await openEdit(tester, inList('Grossa'));
    await tester.scrollUntilVisible(
      find.byKey(const Key('garment-material')),
      300,
      scrollable: find
          .descendant(of: find.byType(Form), matching: find.byType(Scrollable))
          .first,
    );
    expect(find.widgetWithText(TextFormField, 'Lã'), findsOneWidget);
  });
}
