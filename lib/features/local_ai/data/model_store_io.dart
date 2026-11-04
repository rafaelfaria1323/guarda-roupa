import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../domain/local_model.dart';
import 'model_download.dart';

/// Modelos num diretório de suporte da app (fora das cópias de segurança do
/// utilizador e fora da base sincronizada).
final class FileModelStore implements ModelStore {
  FileModelStore({http.Client? client, Future<Directory> Function()? root})
    : _client = client ?? http.Client(),
      _root = root ?? getApplicationSupportDirectory;

  final http.Client _client;
  final Future<Directory> Function() _root;

  Future<File> _file(LocalModel model) async =>
      File('${(await _root()).path}/models/${model.fileName}');

  @override
  Future<bool> isReady(LocalModel model) async {
    final file = await _file(model);
    // O tamanho chega: o ficheiro só aparece com este nome depois de
    // confirmado o sha256.
    return await file.exists() && await file.length() == model.bytes;
  }

  @override
  Future<void> download(
    LocalModel model, {
    required void Function(double progress) onProgress,
  }) async {
    final bytes = await fetchModel(
      _client,
      model,
      model.url,
      onProgress: onProgress,
    );
    final file = await _file(model);
    await file.parent.create(recursive: true);
    final tmp = File('${file.path}.part');
    await tmp.writeAsBytes(bytes, flush: true);
    if (sha256.convert(await tmp.readAsBytes()).toString() != model.sha256) {
      await tmp.delete();
      throw const ModelDownloadException('Erro ao gravar');
    }
    await tmp.rename(file.path);
  }

  @override
  Future<void> remove(LocalModel model) async {
    final file = await _file(model);
    if (await file.exists()) await file.delete();
  }

  @override
  Future<String> location(LocalModel model) async => (await _file(model)).path;
}

ModelStore createModelStore() => FileModelStore();
