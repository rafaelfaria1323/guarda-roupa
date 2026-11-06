import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/account_sync/application/providers.dart';

/// Claro, escuro ou como o aparelho (docs/design-e-fluxos.md). Guarda-se
/// neste aparelho (`local_settings`, `theme_mode`); antes de entrar na conta
/// segue o aparelho.
final themeModeProvider = AsyncNotifierProvider<AppThemeMode, ThemeMode>(
  AppThemeMode.new,
);

class AppThemeMode extends AsyncNotifier<ThemeMode> {
  static const _key = 'theme_mode';

  @override
  Future<ThemeMode> build() async {
    final db = ref.watch(userDatabaseProvider).value;
    if (db == null) return ThemeMode.system;
    final row = await db.getOptional(
      'SELECT value FROM local_settings WHERE key = ?',
      [_key],
    );
    return ThemeMode.values.asNameMap()[row?['value']] ?? ThemeMode.system;
  }

  Future<void> set(ThemeMode mode) async {
    final db = ref.read(userDatabaseProvider).value;
    if (db == null) return;
    await db.execute(
      'INSERT OR REPLACE INTO local_settings (key, value) VALUES (?, ?)',
      [_key, mode.name],
    );
    if (ref.mounted) state = AsyncData(mode);
  }
}
