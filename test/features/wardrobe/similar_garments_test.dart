import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:guarda_roupa/core/domain/result.dart';
import 'package:guarda_roupa/features/local_ai/application/similar_garments_finder.dart';
import 'package:guarda_roupa/features/local_ai/data/photo_embeddings.dart';
import 'package:guarda_roupa/features/wardrobe/data/photo_processor.dart';
import 'package:guarda_roupa/features/wardrobe/data/powersync_wardrobe_repository.dart';
import 'package:guarda_roupa/features/wardrobe/domain/availability.dart';
import 'package:guarda_roupa/features/wardrobe/domain/category_suggestion.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment_category.dart';
import 'package:guarda_roupa/features/wardrobe/domain/similar_garments.dart';

import '../../support/fake_models.dart';
import '../../support/fake_photos.dart';
import '../../support/test_database.dart';

Float32List v(List<double> x) => FashionClip.normalize(x);

T ok<T, F>(Result<T, F> r) => switch (r) {
  Ok(:final value) => value,
  Err(:final failure) => fail('Esperava sucesso, obteve $failure'),
};

void main() {
  group('SimilarGarments.rank', () {
    Garment g(String id) => Garment(
      id: GarmentId(id),
      category: GarmentCategory.tShirt,
      availability: Availability.available,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );

    test('ordena por cosseno, empates pela ordem, ignora outra dimensão', () {
      final ranked = SimilarGarments.rank(v([1, 0]), [
        (g('a'), v([0, 1])),
        (g('b'), v([1, 0.1])),
        (g('c'), v([1, 1])),
        (g('d'), v([1, 1])),
        (g('e'), v([1, 0, 0])),
      ], top: 3);
      expect([for (final (x, _) in ranked) x.id.value], ['b', 'c', 'd']);
      expect(ranked.first.$2, closeTo(0.995, 0.001));
    });

    test('no máximo cinco', () {
      final many = [
        for (var i = 0; i < 8; i++) (g('$i'), v([1, i * 0.1])),
      ];
      expect(SimilarGarments.rank(v([1, 0]), many), hasLength(5));
    });
  });

  test('PhotoEmbeddings guarda e lê por foto e modelo', () async {
    final db = await openTestDatabase();
    final e = Float32List.fromList([0.25, -1, 3.5]);
    await db.writeTransaction((tx) => PhotoEmbeddings.put(tx, 'p1', 'm', e));
    expect(await PhotoEmbeddings.get(db, 'p1', 'm'), e);
    expect(await PhotoEmbeddings.get(db, 'p1', 'outro'), isNull);
    await db.writeTransaction(PhotoEmbeddings.clear);
    expect(await PhotoEmbeddings.get(db, 'p1', 'm'), isNull);
  });

  test('SimilarGarmentsFinder: cada capa analisa-se uma vez; '
      'sem foto não conta; foto que falta fica de fora', () async {
    final db = await openTestDatabase();
    final repo = PowerSyncWardrobeRepository(db: db, ownerId: 'u1');
    final embedder = FakeImageEmbedder();
    final finder = SimilarGarmentsFinder(embedder, db, repo);

    Future<Garment> add(String name, {int? r}) async {
      final created = ok(
        await repo.addGarment(
          GarmentDraft(category: GarmentCategory.tShirt, name: name),
        ),
      );
      if (r == null) return created;
      final photo = ok(processPhotoSync(testPng(width: 64, height: 64, r: r)));
      return ok(await repo.addPhoto(created.id, photo));
    }

    final red = await add('Vermelha', r: 250);
    final dark = await add('Escura', r: 10);
    final mid = await add('Média', r: 130);
    final none = await add('Sem foto');
    // Uma peça vinda de outro dispositivo, sem os bytes aqui.
    final away = await add('Longe', r: 200);
    await db.execute('DELETE FROM photo_files WHERE photo_id = ?', [
      away.photos.first.id,
    ]);

    final all = [dark, none, mid, red, away];
    final first = (await finder.find(testPng(r: 240), all))!;
    expect(
      [for (final (g, _) in first.items) g.name],
      ['Vermelha', 'Média', 'Escura'],
    );
    expect(first.skipped, 1);
    expect(embedder.calls, 1 + 3);

    final progress = <(int, int)>[];
    await finder.find(
      testPng(r: 240),
      all,
      onProgress: (d, t) => progress.add((d, t)),
    );
    expect(embedder.calls, 4 + 1 + 0, reason: 'capas da cache');
    expect(progress.last, (4, 4));

    expect(await finder.find(Uint8List(3), all), isNull);
  });
}
