import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../domain/local_model.dart';

/// Descarrega [url] e confirma tamanho e sha256 de [model]. Lança
/// [ModelDownloadException] se a resposta não servir.
Future<Uint8List> fetchModel(
  http.Client client,
  LocalModel model,
  Uri url, {
  required void Function(double progress) onProgress,
}) async {
  final response = await client.send(http.Request('GET', url));
  if (response.statusCode != 200) {
    throw ModelDownloadException('HTTP ${response.statusCode}');
  }
  final out = BytesBuilder(copy: false);
  await for (final chunk in response.stream) {
    out.add(chunk);
    if (out.length > model.bytes) {
      throw const ModelDownloadException('Maior do que o esperado');
    }
    onProgress(out.length / model.bytes);
  }
  final bytes = out.takeBytes();
  if (bytes.length != model.bytes ||
      sha256.convert(bytes).toString() != model.sha256) {
    throw const ModelDownloadException('Ficheiro diferente do esperado');
  }
  return bytes;
}

final class ModelDownloadException implements Exception {
  const ModelDownloadException(this.message);
  final String message;

  @override
  String toString() => 'ModelDownloadException: $message';
}
