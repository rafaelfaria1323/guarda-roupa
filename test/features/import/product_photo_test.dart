import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:guarda_roupa/features/import/domain/product_photo.dart';
import 'package:guarda_roupa/features/local_ai/data/embedding_photo_scorer.dart';

/// Nota cada foto pela ordem em que é olhada.
final class ScriptedScorer implements ProductPhotoScorer {
  ScriptedScorer(this.scores);

  final List<double?> scores;
  var calls = 0;

  @override
  double get threshold => 0.02;

  @override
  Future<double?> score(Uint8List bytes) async => scores[calls++];
}

void main() {
  final urls = ['a', 'b', 'c', 'd', 'e'];
  late List<String> fetched;
  Future<Uint8List?> fetch(String url) async {
    fetched.add(url);
    return Uint8List.fromList(url.codeUnits);
  }

  setUp(() => fetched = []);

  test('sem IA: só a primeira, como antes', () async {
    final p = await pickProductPhoto(urls, fetch: fetch);
    expect(p?.url, 'a');
    expect(fetched, ['a']);
  });

  test('a primeira já é só a peça: não copia mais nenhuma', () async {
    final p = await pickProductPhoto(
      urls,
      fetch: fetch,
      scorer: ScriptedScorer([0.05]),
    );
    expect(p?.url, 'a');
    expect(fetched, ['a']);
  });

  test('salta o manequim e pára na primeira só da peça', () async {
    final seen = <String>[];
    final p = await pickProductPhoto(
      urls,
      fetch: fetch,
      scorer: ScriptedScorer([-0.03, 0.0, 0.04]),
      fetched: (url, _) => seen.add(url),
    );
    expect(p?.url, 'c');
    expect(String.fromCharCodes(p!.bytes), 'c');
    expect(fetched, ['a', 'b', 'c']);
    expect(seen, ['a', 'b', 'c']);
  });

  test('nenhuma passa: a mais "sozinha" se for neutra, até 4 fotos', () async {
    final p = await pickProductPhoto(
      urls,
      fetch: fetch,
      scorer: ScriptedScorer([-0.03, 0.01, 0.015, -0.01]),
    );
    expect(p?.url, 'c');
    expect(fetched, ['a', 'b', 'c', 'd']);
  });

  test('todas com pessoa: fica a primeira', () async {
    final p = await pickProductPhoto(
      urls,
      fetch: fetch,
      scorer: ScriptedScorer([-0.03, -0.01, -0.02, -0.04]),
    );
    expect(p?.url, 'a');
  });

  test('uma foto que falha conta como vista', () async {
    final p = await pickProductPhoto(
      urls,
      fetch: (url) async {
        fetched.add(url);
        return url == 'a' ? null : Uint8List(1);
      },
      scorer: ScriptedScorer([null, 0.03]),
    );
    expect(p?.url, 'c');
    expect(fetched, ['a', 'b', 'c']);
  });

  test('sem fotos: nada', () async {
    expect(await pickProductPhoto(const [], fetch: fetch), isNull);
  });

  test('os textos do FashionCLIP no asset servem', () {
    final json = jsonDecode(
      File('assets/models/fashionclip_photo_kind.json').readAsStringSync(),
    );
    final texts = PhotoKindTexts.fromJson(json)!;
    expect(texts.worn, hasLength(512));
    expect(texts.threshold, greaterThan(0));
    // Uma imagem igual ao texto "sozinha" pontua positivo.
    expect(texts.score(texts.alone), greaterThan(0));
    expect(texts.score(texts.worn), lessThan(0));
    expect(texts.score(Float32List(3)), isNull);
    expect(
      PhotoKindTexts.fromJson({
        'worn': [1],
        'alone': [1, 2],
      }),
      isNull,
    );
  });
}
