import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guarda_roupa/core/domain/result.dart';
import 'package:guarda_roupa/features/local_ai/application/local_ai_providers.dart';
import 'package:guarda_roupa/features/wardrobe/data/powersync_wardrobe_repository.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment_category.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment_photo.dart';
import 'package:powersync/powersync.dart';

import '../../support/app_harness.dart';
import '../../support/fake_models.dart';

void main() {
  Future<void> addGarment(
    WidgetTester tester,
    PowerSyncDatabase db, {
    required bool photo,
  }) async {
    final repo = PowerSyncWardrobeRepository(db: db, ownerId: 'user-a');
    await tester.runAsync(() async {
      final added = await repo.addGarment(
        const GarmentDraft(category: GarmentCategory.tShirt),
      );
      if (!photo) return;
      final g = (added as Ok<Garment, Object>).value;
      await repo.addPhoto(
        g.id,
        ProcessedPhoto(
          width: 800,
          height: 1000,
          main: Uint8List.fromList(List.filled(32, 7)),
          thumb: Uint8List.fromList(List.filled(8, 7)),
          sha256: '07' * 32,
        ),
      );
    });
    await settle(tester);
  }

  Future<void> finish(WidgetTester tester, FakeModelStore store) async {
    await store.pending!.close();
    await settle(tester);
  }

  testWidgets('com a primeira peça com foto descarrega o recorte e depois o '
      'FashionCLIP, uma vez', (tester) async {
    final store = FakeModelStore();
    final app = await pumpApp(
      tester,
      modelsAuto: true,
      overrides: [modelStoreProvider.overrideWithValue(store)],
    );

    await addGarment(tester, app.db, photo: false);
    expect(store.pending, isNull, reason: 'sem fotos não descarrega');

    await addGarment(tester, app.db, photo: true);
    expect(store.pending, isNotNull);
    await finish(tester, store);
    expect(store.ready, {'u2netp'});
    await finish(tester, store);
    expect(store.ready, {'u2netp', 'fashionclip_q4'});
  });

  testWidgets('removido pelo utilizador, não volta sozinho', (tester) async {
    final store = FakeModelStore();
    final app = await pumpApp(
      tester,
      modelsAuto: true,
      overrides: [modelStoreProvider.overrideWithValue(store)],
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );
    await tester.runAsync(
      () => container
          .read(localAiAutoOptOutProvider.notifier)
          .set(optedOut: true),
    );
    await settle(tester);

    await addGarment(tester, app.db, photo: true);
    expect(store.pending, isNull);
  });
}
