import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// `onnxruntime-web` (só WASM), servido pelo próprio site em `ort/` (ver
/// tool/models/fetch_models.sh). Carrega-se quando um modelo se usa pela
/// primeira vez: quem não ativa a IA local não descarrega o runtime
/// (~11 MB com o WASM).
const ortWebVersion = '1.22.0';

Future<void>? _loading;

Future<void> ensureOrtLoaded() => _loading ??= _load().catchError((Object e) {
  _loading = null;
  throw e;
});

Future<void> _load() {
  final done = Completer<void>();
  final script = web.document.createElement('script') as web.HTMLScriptElement
    ..src = Uri.base.resolve('ort/ort.wasm.min.js').toString();
  script.onload = ((web.Event _) => done.complete()).toJS;
  script.onerror = ((web.Event _) => done.completeError(
    StateError('onnxruntime-web indisponível'),
  )).toJS;
  web.document.head!.append(script);
  return done.future;
}
