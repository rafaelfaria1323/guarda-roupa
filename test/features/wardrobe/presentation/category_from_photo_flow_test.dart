import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guarda_roupa/features/local_ai/application/local_ai_providers.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment_category.dart';

import '../../../support/app_harness.dart';
import '../../../support/fake_models.dart';
import '../../../support/fake_photos.dart';
import 'photos_flow_test.dart' show start;

const _button = Key('category-from-photo');

void main() {
  Future<void> addPhoto(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(const Key('photo-gallery')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('photo-gallery')));
    await settleUntil(tester, find.byType(Image));
  }

  testWidgets('sugere, só muda com um toque e guarda a escolhida', (
    tester,
  ) async {
    final suggester = FakeCategorySuggester(const [
      GarmentCategory.shirt,
      GarmentCategory.tShirt,
      GarmentCategory.polo,
    ]);
    final app = await start(
      tester,
      overrides: [categorySuggesterProvider.overrideWithValue(suggester)],
    );
    app.picker.next.add(testPng());

    await tester.tap(find.text('Adicionar peça'));
    await settle(tester);
    expect(find.byKey(_button), findsNothing); // sem foto

    await addPhoto(tester);
    await tester.ensureVisible(find.byKey(_button));
    await tester.pump();
    await tester.tap(find.byKey(_button));
    await settle(tester);
    expect(suggester.calls, 1);
    expect(
      find.text('Sugestões pela foto (toca para escolher):'),
      findsOneWidget,
    );
    for (final id in ['shirt', 't_shirt', 'polo']) {
      expect(find.byKey(Key('category-suggestion-$id')), findsOneWidget);
    }
    // Sugerir não escolhe: o campo continua vazio.
    expect(
      find.descendant(
        of: find.byKey(const Key('garment-category')),
        matching: find.text('Camisa'),
      ),
      findsNothing,
    );

    await tester.tap(find.byKey(const Key('category-suggestion-shirt')));
    await tester.pump();
    expect(
      find.descendant(
        of: find.byKey(const Key('garment-category')),
        matching: find.text('Camisa'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('category-suggestion-polo')), findsNothing);

    await tester.tap(find.byKey(const Key('garment-save')));
    await settleUntil(
      tester,
      find.byKey(const Key('garment-save')),
      gone: true,
    );
    final row = (await tester.runAsync(
      () => app.db.get('SELECT category FROM garments'),
    ))!;
    expect(row['category'], 'shirt');
  });

  testWidgets('sem resultado avisa e o formulário segue manual', (
    tester,
  ) async {
    final app = await start(
      tester,
      overrides: [
        categorySuggesterProvider.overrideWithValue(
          FakeCategorySuggester(null),
        ),
      ],
    );
    app.picker.next.add(testPng());
    await tester.tap(find.text('Adicionar peça'));
    await settle(tester);
    await addPhoto(tester);
    await tester.ensureVisible(find.byKey(_button));
    await tester.pump();
    await tester.tap(find.byKey(_button));
    await settle(tester);
    expect(
      find.text('Não foi possível sugerir a categoria por esta foto.'),
      findsOneWidget,
    );
    expect(find.byKey(_button), findsOneWidget);
  });

  testWidgets('sem o modelo não há botão', (tester) async {
    final app = await start(tester);
    app.picker.next.add(testPng());
    await tester.tap(find.text('Adicionar peça'));
    await settle(tester);
    await addPhoto(tester);
    expect(find.byKey(_button), findsNothing);
  });
}
