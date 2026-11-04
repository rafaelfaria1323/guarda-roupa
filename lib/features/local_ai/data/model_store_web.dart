import 'dart:js_interop';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:web/web.dart' as web;

import '../domain/local_model.dart';
import 'model_download.dart';

/// Na Web os modelos ficam na Cache Storage do browser (persistente, mas o
/// browser pode limpá-la se faltar espaço: o modelo volta a "por
/// descarregar"). Abrem-se por um URL `blob:`, sem voltar à rede.
final class WebModelStore implements ModelStore {
  WebModelStore({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const _cacheName = 'local-models';

  /// Chave da cache: muda com o sha256, para uma versão nova não usar a
  /// antiga.
  static String _key(LocalModel model) =>
      Uri.base.resolve('local-models/${model.id}/${model.sha256}').toString();

  Uri _source(LocalModel model) =>
      model.webUrl ?? Uri.base.resolve('models/${model.fileName}');

  Future<web.Cache> _cache() => web.window.caches.open(_cacheName).toDart;

  Future<web.Response?> _match(LocalModel model) async =>
      (await _cache()).match(_key(model).toJS).toDart;

  @override
  Future<bool> isReady(LocalModel model) async {
    try {
      return await _match(model) != null;
    } on Object {
      return false;
    }
  }

  @override
  Future<void> download(
    LocalModel model, {
    required void Function(double progress) onProgress,
  }) async {
    final parts = <JSUint8Array>[];
    await fetchModel(
      _client,
      model,
      _source(model),
      onProgress: onProgress,
      onChunk: (Uint8List c) => parts.add(c.toJS),
    );
    final blob = web.Blob(parts.toJS);
    await (await _cache()).put(_key(model).toJS, web.Response(blob)).toDart;
  }

  @override
  Future<void> remove(LocalModel model) async {
    await (await _cache()).delete(_key(model).toJS).toDart;
  }

  @override
  Future<String> location(LocalModel model) async {
    final hit = await _match(model);
    if (hit == null) throw StateError('Modelo por descarregar');
    final blob = await hit.blob().toDart;
    return web.URL.createObjectURL(blob);
  }
}

ModelStore createModelStore() => WebModelStore();
