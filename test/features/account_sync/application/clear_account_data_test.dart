import 'package:flutter_test/flutter_test.dart';
import 'package:guarda_roupa/features/account_sync/application/providers.dart';
import 'package:guarda_roupa/features/wardrobe/data/powersync_wardrobe_repository.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment_category.dart';

import '../../../support/test_database.dart';

void main() {
  test('terminar sessão apaga peças, fila e fotografias locais', () async {
    final db = await openTestDatabase();
    final repo = PowerSyncWardrobeRepository(db: db, ownerId: 'user-a');
    await repo.addGarment(const GarmentDraft(category: GarmentCategory.shirt));
    await db.execute("INSERT INTO photo_files VALUES ('p1', 'thumb', x'00')");

    await clearAccountData(db);

    expect(await db.getAll('SELECT * FROM garments'), isEmpty);
    expect(await db.getAll('SELECT * FROM photo_files'), isEmpty);
    expect(await pendingOperations(db), isEmpty);
  });
}
