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
    await settleUntil(tester, find.textContaining('2 peças'));
    expect(
      tester.widget<Text>(find.byKey(const Key('profile-stats'))).data,
      '2 peças · 0 conjuntos · 0 inspirações',
    );

    await tester.tap(find.byKey(const Key('profile-settings')));
    await settle(tester);
    expect(find.text('Aspeto'), findsOne);
  });
}
