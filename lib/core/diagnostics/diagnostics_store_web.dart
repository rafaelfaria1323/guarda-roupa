import 'package:web/web.dart' as web;

import 'diagnostics_store.dart';

export 'diagnostics_store.dart';

DiagnosticsStore platformDiagnosticsStore() => _LocalStorageStore();

/// O browser e o sistema, para o cabeçalho do relatório.
String platformDescription() => web.window.navigator.userAgent;

final class _LocalStorageStore implements DiagnosticsStore {
  static const _key = 'fio.diagnostics';

  @override
  String? read() {
    try {
      return web.window.localStorage.getItem(_key);
    } on Object {
      return null;
    }
  }

  @override
  void write(String value) => web.window.localStorage.setItem(_key, value);
}
