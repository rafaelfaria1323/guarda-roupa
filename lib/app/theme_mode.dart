import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'device_prefs.dart';

/// Claro, escuro ou como o aparelho (docs/design-e-fluxos.md). Fica só neste
/// aparelho (`localStorage`, `fio.theme_mode`) e lê-se logo ao abrir, antes
/// de entrar na conta, para a app não piscar em claro.
final themeModeProvider = NotifierProvider<AppThemeMode, ThemeMode>(
  AppThemeMode.new,
);

class AppThemeMode extends Notifier<ThemeMode> {
  static const key = 'fio.theme_mode';

  @override
  ThemeMode build() =>
      ThemeMode.values.asNameMap()[devicePrefs.get(key)] ?? ThemeMode.system;

  void set(ThemeMode mode) {
    devicePrefs.set(key, mode.name);
    state = mode;
  }
}
