import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../domain/local_model.dart';

/// Descarrega [url] aos bocados para [onChunk], a confirmar tamanho e
/// sha256 de [model] pelo caminho (sem ter o ficheiro todo em memória).
/// Lança [ModelDownloadException] se a resposta não servir; quem chama
/// deita fora o que recebeu.
Future<void> fetchModel(
  http.Client client,
  LocalModel model,
  Uri url, {
  required void Function(double progress) onProgress,
  required void Function(Uint8List chunk) onChunk,
}) async {
  final response = await client.send(http.Request('GET', url));
  if (response.statusCode != 200) {
    throw ModelDownloadException('HTTP ${response.statusCode}');
  }
  final digest = _DigestSink();
  final hash = sha256.startChunkedConversion(digest);
  var received = 0;
  await for (final chunk in response.stream) {
    received += chunk.length;
    if (received > model.bytes) {
      throw const ModelDownloadException('Maior do que o esperado');
    }
    final bytes = chunk is Uint8List ? chunk : Uint8List.fromList(chunk);
    hash.add(bytes);
    onChunk(bytes);
    onProgress(received / model.bytes);
  }
  hash.close();
  if (received != model.bytes || digest.value.toString() != model.sha256) {
    throw const ModelDownloadException('Ficheiro diferente do esperado');
  }
}

final class _DigestSink implements Sink<Digest> {
  late Digest value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}

final class ModelDownloadException implements Exception {
  const ModelDownloadException(this.message);
  final String message;

  @override
  String toString() => 'ModelDownloadException: $message';
}
