import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guarda_roupa/core/domain/result.dart';
import 'package:guarda_roupa/features/wardrobe/application/garment_copies.dart';
import 'package:guarda_roupa/features/wardrobe/data/powersync_wardrobe_repository.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment_category.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment_photo.dart';
import 'package:guarda_roupa/features/wardrobe/domain/photo_storage.dart';
import 'package:guarda_roupa/features/wardrobe/domain/wardrobe_repository.dart';

import '../../../support/test_database.dart';

T ok<T>(WardrobeResult<T> r) => switch (r) {
  Ok(:final value) => value,
  Err(:final failure) => fail('Esperava sucesso, obteve $failure'),
};

final class _Storage implements PhotoStorage {
  final files = <String, Uint8List>{};

  @override
  Future<Uint8List> download(String path) async =>
      files[path] ?? (throw StateError('sem rede'));

  @override
  Future<void> remove(List<String> paths) async {}

  @override
  Future<void> upload(String path, Uint8List bytes) async =>
      files[path] = bytes;

  @override
  Future<Uri> temporaryLink(String path) => throw UnimplementedError();
}

ProcessedPhoto photo(int seed) {
  final main = Uint8List.fromList([1, 2, seed]);
  return ProcessedPhoto(
    width: 1600,
    height: 1200,
    main: main,
    thumb: Uint8List.fromList([3, seed]),
    sha256: sha256.convert(main).toString(),
  );
}

void main() {
  test('duplicar copia as fotografias com ids novos', () async {
    final db = await openTestDatabase();
    final repo = PowerSyncWardrobeRepository(db: db, ownerId: 'user-a');
    final g = ok(
      await repo.addGarment(
        const GarmentDraft(category: GarmentCategory.tShirt, name: 'Branca'),
      ),
    );
    ok(await repo.addPhoto(g.id, photo(1)));
    final source = ok(await repo.addPhoto(g.id, photo(2)));

    final copy = ok(
      await duplicateGarmentWithPhotos(
        repo,
        source,
        storage: null,
        userId: null,
      ),
    );
    expect(copy.id, isNot(g.id));
    expect(copy.name, 'Branca');
    expect(copy.photos, hasLength(2));
    expect(
      copy.photos.map((p) => p.id).toSet().intersection({
        for (final p in source.photos) p.id,
      }),
      isEmpty,
      reason: 'apagar uma não apaga as da outra',
    );
    expect(await repo.photoBytes(copy.photos.first.id, PhotoVariant.main), [
      1,
      2,
      1,
    ]);
  });

  test('foto que não está aqui descarrega-se; sem rede fica de fora', () async {
    final db = await openTestDatabase();
    final repo = PowerSyncWardrobeRepository(db: db, ownerId: 'user-a');
    final g = ok(
      await repo.addGarment(
        const GarmentDraft(category: GarmentCategory.tShirt, name: 'Branca'),
      ),
    );
    final source = ok(await repo.addPhoto(g.id, photo(1)));
    final p = source.photos.single;
    // Como noutro dispositivo: a peça tem a foto, mas os ficheiros só
    // estão no Storage.
    final storage = _Storage();
    for (final variant in PhotoVariant.values) {
      storage.files[PhotoRules.storagePath('user-a', p.id, variant)] =
          (await repo.photoBytes(p.id, variant))!;
    }
    await db.execute('DELETE FROM photo_files');

    final copy = ok(
      await duplicateGarmentWithPhotos(
        repo,
        source,
        storage: storage,
        userId: 'user-a',
      ),
    );
    expect(copy.photos, hasLength(1));

    final offline = ok(
      await duplicateGarmentWithPhotos(
        repo,
        source,
        storage: _Storage(),
        userId: 'user-a',
      ),
    );
    expect(offline.photos, isEmpty);
  });
}
