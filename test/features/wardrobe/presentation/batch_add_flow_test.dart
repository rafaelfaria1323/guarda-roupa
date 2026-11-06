import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guarda_roupa/features/local_ai/application/local_ai_providers.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment_category.dart';
import 'package:powersync/powersync.dart';

import '../../../support/app_harness.dart';
import '../../../support/fake_models.dart';
import '../../../support/fake_photos.dart';
import 'photos_flow_test.dart' show start;

Future<List<String>> categories(
  WidgetTester tester,
  PowerSyncDatabase db,
) async {
  final rows = await tester.runAsync(
    () => db.getAll('select category from garments order by created_at, id'),
  );
  return [for (final r in rows!) r['category'] as String];
}

Future<void> pickBatch(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('wardrobe-batch')));
  await settle(tester);
  await tester.tap(find.byKey(const Key('batch-pick')));
  await settleUntil(tester, find.byKey(const Key('batch-more')));
}

void main() {
  testWidgets('várias fotos: uma peça por foto, categoria sugerida e '
      'confirmada com um toque', (tester) async {
    final suggester = FakeCategorySuggester(const [
      GarmentCategory.shirt,
      GarmentCategory.tShirt,
      GarmentCategory.polo,
    ]);
    final app = await start(
      tester,
      overrides: [categorySuggesterProvider.overrideWithValue(suggester)],
    );
    app.picker.nextMany = [
      testPng(),
      Uint8List.fromList([1, 2, 3]),
      testPng(r: 30),
    ];

    await pickBatch(tester);
    expect(app.picker.manyLimits, [20]);
    expect(find.text('2 peças criadas'), findsOneWidget);
    expect(
      find.text(
        'Este ficheiro não é uma imagem suportada (JPEG, PNG ou WebP).',
      ),
      findsOneWidget,
    );
    expect(find.text('Categoria sugerida'), findsNWidgets(2));
    expect(await categories(tester, app.db), ['shirt', 'shirt']);

    // Um toque na segunda sugestão muda a primeira peça.
    await tester.tap(find.widgetWithText(ChoiceChip, 'T-shirt').first);
    await settle(tester);
    // "Outra…" escolhe qualquer categoria.
    await tester.tap(find.widgetWithText(ActionChip, 'Outra…').last);
    await settle(tester);
    await tester.ensureVisible(find.byKey(const Key('batch-category-jeans')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('batch-category-jeans')));
    await settleUntil(tester, find.text('Categoria sugerida'), gone: true);
    expect(find.widgetWithText(ChoiceChip, 'Calças de ganga'), findsOneWidget);
    expect(await categories(tester, app.db), ['t_shirt', 'jeans']);

    await tester.tap(find.byKey(const Key('batch-done')));
    await settle(tester);
    expect(find.byKey(const Key('wardrobe-batch')), findsOneWidget);
    expect(find.text('2 peças'), findsOneWidget);
  });

  testWidgets('sem o modelo: entram como "Outra" e escolhe-se aqui', (
    tester,
  ) async {
    final app = await start(tester);
    app.picker.nextMany = [testPng()];

    await tester.tap(find.byKey(const Key('wardrobe-batch')));
    await settle(tester);
    expect(find.textContaining('IA local'), findsOneWidget);
    await tester.tap(find.byKey(const Key('batch-pick')));
    await settleUntil(tester, find.byKey(const Key('batch-more')));

    expect(find.text('1 peça criada'), findsOneWidget);
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Outra'))
          .selected,
      isTrue,
    );
    expect(await categories(tester, app.db), ['other']);
  });

  testWidgets('cancelar a galeria não cria nada', (tester) async {
    final app = await start(tester);
    await tester.tap(find.byKey(const Key('wardrobe-batch')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('batch-pick')));
    await settle(tester);
    expect(find.byKey(const Key('batch-list')), findsNothing);
    expect(await categories(tester, app.db), isEmpty);
  });
}
