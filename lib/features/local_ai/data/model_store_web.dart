import 'package:http/http.dart' as http;
import 'package:web/web.dart' as web;

import '../domain/local_model.dart';
import 'model_download.dart';

/// Na Web o modelo vem do próprio site (`models/<ficheiro>`, ver
/// tool/models/fetch_models.sh) e fica na cache do browser. Descarregar
/// confirma o ficheiro e regista o acordo do utilizador neste browser.
final class WebModelStore implements ModelStore {
  WebModelStore({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static String _key(LocalModel model) => 'local_model_${model.id}';

  Uri _url(LocalModel model) => Uri.base.resolve('models/${model.fileName}');

  @override
  Future<bool> isReady(LocalModel model) async {
    try {
      return web.window.localStorage.getItem(_key(model)) == model.sha256;
    } on Object {
      return false;
    }
  }

  @override
  Future<void> download(
    LocalModel model, {
    required void Function(double progress) onProgress,
  }) async {
    await fetchModel(_client, model, _url(model), onProgress: onProgress);
    web.window.localStorage.setItem(_key(model), model.sha256);
  }

  @override
  Future<void> remove(LocalModel model) async {
    web.window.localStorage.removeItem(_key(model));
  }

  @override
  Future<String> location(LocalModel model) async => _url(model).toString();
}

ModelStore createModelStore() => WebModelStore();
