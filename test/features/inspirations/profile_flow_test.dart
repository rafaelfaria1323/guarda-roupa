import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guarda_roupa/features/wardrobe/data/powersync_wardrobe_repository.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment_category.dart';

import '../../support/app_harness.dart';

void main() {
  testWidgets('Perfil: conta, resumo do armário e entrada para Definições', (
    tester,
  ) async {
    final (:auth, :db) = await pumpApp(tester);
    await tester.runAsync(() async {
      final repo = PowerSyncWardrobeRepository(db: db, ownerId: 'user-a');
      for (final name in ['Branca', 'Azul']) {
        await repo.addGarment(
          GarmentDraft(category: GarmentCategory.tShirt, name: name),
        );
      }
    });
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Perfil'),
      ),
    );
    String stat(String key) =>
        tester.widget<Text>(find.byKey(Key('profile-stat-$key'))).data!;
    await settle(tester);
    expect(stat('garments'), '2');
    expect(stat('outfits'), '0');
    expect(stat('inspirations'), '0');
    expect(stat('rotation'), '0%', reason: 'nada vestido nos últimos 30 dias');

    await tester.tap(find.byKey(const Key('profile-settings')));
    await settle(tester);
    expect(find.text('Aspeto'), findsOne);
    await tester.tap(find.byTooltip('Voltar'));
    await settle(tester);

    // Atalhos no fim da página.
    await tester.scrollUntilVisible(
      find.byKey(const Key('profile-link-comfort')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('profile-link-comfort')));
    await settle(tester);
    expect(find.widgetWithText(AppBar, 'Conforto e tempo'), findsOne);
  });
}
