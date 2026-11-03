import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guarda_roupa/core/domain/result.dart';
import 'package:guarda_roupa/features/backup/data/backup_codec.dart';
import 'package:guarda_roupa/features/backup/data/backup_exporter.dart';
import 'package:guarda_roupa/features/backup/domain/backup.dart';
import 'package:guarda_roupa/features/wardrobe/data/powersync_wardrobe_repository.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment_attributes.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment_category.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment_color.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment_photo.dart';
import 'package:powersync/powersync.dart';

import '../../support/test_database.dart';

T ok<T, F>(Result<T, F> r) => switch (r) {
  Ok(:final value) => value,
  Err(:final failure) => fail('Esperava sucesso, obteve $failure'),
};

ProcessedPhoto photo(int seed) {
  final main = Uint8List.fromList(List.generate(50, (i) => (i * seed) % 256));
  return ProcessedPhoto(
    width: 10,
    height: 8,
    main: main,
    thumb: Uint8List.fromList([seed, seed]),
    sha256: sha256.convert(main).toString(),
  );
}

/// Reescreve um ZIP aplicando [edit] a cada ficheiro (nome → bytes).
Uint8List rewrite(
  Uint8List zip,
  Map<String, Uint8List>? Function(String name, Uint8List bytes) edit,
) {
  final out = Archive();
  for (final f in ZipDecoder().decodeBytes(zip)) {
    final replaced = edit(f.name, f.content) ?? {f.name: f.content};
    for (final MapEntry(:key, :value) in replaced.entries) {
      out.add(ArchiveFile.bytes(key, value));
    }
  }
  return ZipEncoder().encodeBytes(out);
}

Map<String, Object?> manifestOf(Uint8List zip) => jsonDecode(
  utf8.decode(ZipDecoder().decodeBytes(zip).findFile('manifest.json')!.content),
) as Map<String, Object?>;

Uint8List withManifest(
  Uint8List zip,
  void Function(Map<String, Object?> m) edit,
) {
  final m = manifestOf(zip);
  edit(m);
  return rewrite(
    zip,
    (name, bytes) =>
        name == 'manifest.json' ? {name: utf8.encode(jsonEncode(m))} : null,
  );
}

void main() {
  late PowerSyncDatabase db;
  late PowerSyncWardrobeRepository repo;

  setUp(() async {
    db = await openTestDatabase();
    repo = PowerSyncWardrobeRepository(db: db, ownerId: 'user-a');
  });

  Future<Garment> add(GarmentDraft draft, {int photos = 0}) async {
    var g = ok(await repo.addGarment(draft));
    for (var i = 0; i < photos; i++) {
      g = ok(await repo.addPhoto(g.id, photo(i + 3)));
    }
    return g;
  }

  Future<Uint8List> export({RemotePhoto? remote}) async =>
      ok(await BackupExporter(db: db, remote: remote).export());

  group('exportar e ler', () {
    test('ida e volta: peças, atributos e fotos intactos', () async {
      final a = await add(
        GarmentDraft(
          category: GarmentCategory.sweater,
          name: 'Grossa',
          colors: [GarmentColor.create(rgb: 0x1F2A44, proportion: 0.7)!],
          attributes: const GarmentAttributes(
            warmth: Warmth.warm,
            rainOk: false,
            occasions: {Occasion.evening},
            material: 'Lã',
          ),
        ),
        photos: 2,
      );
      final b = await add(const GarmentDraft(category: GarmentCategory.skirt));
      ok(await repo.archiveGarment(b.id));
      final deleted = await add(
        const GarmentDraft(category: GarmentCategory.coat),
      );
      ok(await repo.deleteGarment(deleted.id));

      final zip = await export();
      final contents = ok(BackupCodec.decode(zip));

      expect(contents.summary.garments, 2, reason: 'eliminadas ficam fora');
      expect(contents.summary.photos, 2);
      expect(contents.summary.pendingOperations, greaterThan(0));
      final restored = {for (final g in contents.garments) g.id: g};
      final current = (await repo.watchGarment(a.id).first)!;
      expect(restored[a.id]!.name, 'Grossa');
      expect(restored[a.id]!.attributes, current.attributes);
      expect(restored[a.id]!.colors.single.rgb, 0x1F2A44);
      expect(restored[a.id]!.photos, current.photos);
      expect(restored[b.id]!.isArchived, isTrue);
      final first = current.photos.first;
      expect(contents.photoFiles[(first.id, PhotoVariant.main)], photo(3).main);
    });

    test('manifest com versão, contagens e hashes; sem segredos', () async {
      await add(const GarmentDraft(category: GarmentCategory.shirt), photos: 1);
      final m = manifestOf(await export());
      expect(m['format'], 'guarda-roupa-backup');
      expect(m['version'], 1);
      expect(m['counts'], {'garments': 1, 'photos': 2});
      final files = (m['files']! as List).cast<Map<String, Object?>>();
      expect(files.map((f) => f['path']), contains('data/garments.json'));
      expect(files.every((f) => (f['sha256']! as String).length == 64), true);
      final text = jsonEncode(m);
      expect(text, isNot(contains('owner_id')));
      expect(text, isNot(contains('token')));
    });

    test('guarda-roupa vazio também exporta', () async {
      final contents = ok(BackupCodec.decode(await export()));
      expect(contents.garments, isEmpty);
    });
  });

  group('fotos que não estão neste dispositivo', () {
    Future<Garment> withRemoteOnlyPhoto() async {
      final g = await add(
        const GarmentDraft(category: GarmentCategory.shirt),
        photos: 1,
      );
      await db.execute('DELETE FROM photo_files');
      return g;
    }

    test('descarrega da cloud', () async {
      final g = await withRemoteOnlyPhoto();
      final asked = <String>[];
      final zip = await export(
        remote: (p, v) async {
          asked.add('${p.id}/${v.id}');
          return photo(3).bytesOf(v);
        },
      );
      expect(asked, hasLength(2));
      expect(ok(BackupCodec.decode(zip)).summary.photos, 1);
      expect(g.photos, hasLength(1));
    });

    test('sem rede: falha explícita, sem ficheiro incompleto', () async {
      await withRemoteOnlyPhoto();
      final r = await BackupExporter(
        db: db,
        remote: (_, _) async => throw Exception('sem rede'),
      ).export();
      final failure = (r as Err<Uint8List, BackupProblem>).failure;
      expect(failure, isA<MissingPhotos>());
      expect((failure as MissingPhotos).count, 2);
    });

    test('descarregada mas diferente (hash) conta como em falta', () async {
      await withRemoteOnlyPhoto();
      final r = await BackupExporter(
        db: db,
        remote: (_, v) async => Uint8List.fromList([9, 9, 9]),
      ).export();
      expect((r as Err).failure, isA<MissingPhotos>());
    });
  });

  group('ficheiros inválidos são rejeitados por inteiro', () {
    late Uint8List zip;
    setUp(() async {
      await add(const GarmentDraft(category: GarmentCategory.shirt), photos: 1);
      zip = await export();
    });

    BackupProblem problem(Uint8List bytes) => (BackupCodec.decode(
      bytes,
    ) as Err<BackupContents, BackupProblem>).failure;

    test('não é ZIP', () {
      expect(
        problem(Uint8List.fromList(utf8.encode('olá'))),
        isA<NotABackup>(),
      );
    });

    test('ZIP de outra coisa', () {
      final other = ZipEncoder().encodeBytes(
        Archive()..add(ArchiveFile.string('a.txt', 'x')),
      );
      expect(problem(other), isA<NotABackup>());
    });

    test('versão mais recente', () {
      final p = problem(withManifest(zip, (m) => m['version'] = 2));
      expect(p, isA<UnsupportedBackupVersion>());
      expect((p as UnsupportedBackupVersion).version, 2);
    });

    test('foto alterada', () {
      final bad = rewrite(
        zip,
        (name, bytes) => name.endsWith('main.jpg')
            ? {
                name: Uint8List.fromList([...bytes]..[0] ^= 1),
              }
            : null,
      );
      expect(problem(bad), isA<CorruptBackup>());
    });

    test('foto em falta', () {
      final bad = rewrite(
        zip,
        (name, bytes) => name.endsWith('thumb.jpg') ? {} : null,
      );
      expect(problem(bad), isA<CorruptBackup>());
    });

    test('caminho fora da pasta (..)', () {
      final bad = withManifest(zip, (m) {
        (m['files']! as List).add({
          'path': '../fora.json',
          'size': 1,
          'sha256': '0' * 64,
        });
      });
      expect(problem(bad), isA<CorruptBackup>());
    });

    test('ficheiro extra que o manifest não declara', () {
      final bad = rewrite(
        zip,
        (name, bytes) => name == 'manifest.json'
            ? {name: bytes, 'photos/x/main.jpg': Uint8List(1)}
            : null,
      );
      expect(problem(bad), isA<CorruptBackup>());
    });

    test('peça inválida (hash certo, conteúdo sem categoria)', () {
      final data = utf8.encode(
        jsonEncode({
          'garments': [
            {'id': 'abc', 'availability': 'available'},
          ],
        }),
      );
      var bad = rewrite(
        zip,
        (name, bytes) => name == 'data/garments.json' ? {name: data} : null,
      );
      bad = withManifest(bad, (m) {
        for (final f in (m['files']! as List).cast<Map<String, Object?>>()) {
          if (f['path'] == 'data/garments.json') {
            f['size'] = data.length;
            f['sha256'] = sha256.convert(data).toString();
          }
        }
      });
      expect(problem(bad), isA<CorruptBackup>());
    });
  });

  test('nome do ficheiro com data e hora local', () {
    expect(
      backupFileName(DateTime(2026, 11, 3, 9, 5)),
      'guarda-roupa-2026-11-03-0905',
    );
  });
}
