import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guarda_roupa/core/domain/result.dart';
import 'package:guarda_roupa/features/wardrobe/data/powersync_wardrobe_repository.dart';
import 'package:guarda_roupa/features/wardrobe/domain/availability.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment_category.dart';
import 'package:guarda_roupa/features/wear/application/wear_providers.dart';

import '../../support/app_harness.dart';
import '../wardrobe/domain/fakes.dart';

void main() {
  testWidgets('Hoje: data, lavandaria só com peças a lavar e atalhos', (
    tester,
  ) async {
    final (:auth, :db) = await pumpApp(
      tester,
      overrides: [
        clockProvider.overrideWithValue(
          FixedClock(DateTime.utc(2026, 11, 6, 10)),
        ),
      ],
    );
    expect(find.text('SEXTA-FEIRA, 6 DE NOVEMBRO'), findsOne);
    expect(find.byKey(const Key('today-laundry')), findsNothing);

    final repo = PowerSyncWardrobeRepository(db: db, ownerId: 'user-a');
    await tester.runAsync(() async {
      final added = await repo.addGarment(
        const GarmentDraft(category: GarmentCategory.jeans, name: 'Ganga'),
      );
      await repo.setAvailability(
        (added as Ok<Garment, Object?>).value.id,
        Availability.washing,
      );
    });
    await settleUntil(tester, find.byKey(const Key('today-laundry')));
    expect(find.text('1 peça na lavandaria'), findsOne);

    await tester.ensureVisible(find.byKey(const Key('quick-week')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('quick-week')));
    await settle(tester);
    expect(find.text('A tua semana'), findsOne);
  });
}
