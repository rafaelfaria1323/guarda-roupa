import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guarda_roupa/features/local_ai/data/model_download.dart';
import 'package:guarda_roupa/features/local_ai/data/model_store_io.dart';
import 'package:guarda_roupa/features/local_ai/domain/local_model.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

final payload = Uint8List.fromList(List.generate(1000, (i) => i % 251));

LocalModel modelFor(Uint8List bytes) => LocalModel(
  id: 'test',
  fileName: 'test.onnx',
  url: Uri.parse('https://example.com/test.onnx'),
  sha256: sha256.convert(bytes).toString(),
  bytes: bytes.length,
  license: 'MIT',
);

MockClient serving(Uint8List body, {int status = 200}) =>
    MockClient((req) async => http.Response.bytes(body, status));

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('models'));
  tearDown(() => dir.deleteSync(recursive: true));

  FileModelStore store(http.Client client) =>
      FileModelStore(client: client, root: () async => dir);

  test('descarrega, confirma, fica pronto e remove-se', () async {
    final model = modelFor(payload);
    final s = store(serving(payload));
    expect(await s.isReady(model), isFalse);
    final progress = <double>[];
    await s.download(model, onProgress: progress.add);
    expect(progress.last, 1.0);
    expect(await s.isReady(model), isTrue);
    expect(File(await s.location(model)).readAsBytesSync(), payload);
    await s.remove(model);
    expect(await s.isReady(model), isFalse);
  });

  test('ficheiro diferente do esperado não fica', () async {
    final model = modelFor(payload);
    final other = Uint8List.fromList([...payload]..[0] ^= 1);
    final s = store(serving(other));
    await expectLater(
      s.download(model, onProgress: (_) {}),
      throwsA(isA<ModelDownloadException>()),
    );
    expect(await s.isReady(model), isFalse);
    expect(dir.listSync(recursive: true).whereType<File>(), isEmpty);
  });

  test('erro HTTP ou ficheiro maior falham', () async {
    final model = modelFor(payload);
    await expectLater(
      store(serving(payload, status: 404)).download(model, onProgress: (_) {}),
      throwsA(isA<ModelDownloadException>()),
    );
    await expectLater(
      store(serving(Uint8List.fromList([...payload, 0])))
          .download(model, onProgress: (_) {}),
      throwsA(isA<ModelDownloadException>()),
    );
    expect(await store(serving(payload)).isReady(model), isFalse);
  });

  test('o modelo de recorte aponta para o ficheiro confirmado', () {
    final m = LocalModels.background;
    expect(m.sha256, hasLength(64));
    expect(m.url.scheme, 'https');
    expect(m.url.path, endsWith(m.fileName));
  });
}
