import 'package:web/web.dart' as web;

import 'device_prefs_io.dart' show DevicePrefs;

/// No browser ficam no `localStorage`, que pode estar bloqueado (janela
/// privada, dados apagados): nesse caso a app segue sem a preferência.
final class _LocalStoragePrefs implements DevicePrefs {
  @override
  String? get(String key) {
    try {
      return web.window.localStorage.getItem(key);
    } on Object {
      return null;
    }
  }

  @override
  void set(String key, String value) {
    try {
      web.window.localStorage.setItem(key, value);
    } on Object {
      // Sem armazenamento: vale só até fechar a app.
    }
  }
}

final DevicePrefs devicePrefs = _LocalStoragePrefs();
