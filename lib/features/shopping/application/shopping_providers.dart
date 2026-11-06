import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/open_link.dart' as platform;
import '../../account_sync/application/providers.dart';
import '../../photo_ai/application/photo_ai_providers.dart';
import '../domain/shopping_advice.dart';

/// Ideias de compra do servidor; `null` sem Supabase (testes, modo local).
final shoppingAdvisorProvider = Provider<ShoppingAdvisor?>((ref) => null);

/// Só com "Usar o Gemini neste aparelho" ligado.
final activeShoppingAdvisorProvider = Provider<ShoppingAdvisor?>((ref) {
  final advisor = ref.watch(shoppingAdvisorProvider);
  if (advisor == null) return null;
  return ref.watch(geminiPhotosProvider).value == true ? advisor : null;
});

/// Abre um link fora da app; `false` se não deu (aí copia-se).
final openLinkProvider = Provider<Future<bool> Function(Uri)>(
  (ref) => platform.openLink,
);

/// Orçamento por peça e ideias postas de lado, neste aparelho.
final class ShoppingSettings {
  const ShoppingSettings({this.budgetEur, this.dismissed = const {}});

  final int? budgetEur;
  final Set<String> dismissed;
}

final shoppingSettingsProvider =
    AsyncNotifierProvider<ShoppingSettingsNotifier, ShoppingSettings>(
      ShoppingSettingsNotifier.new,
    );

class ShoppingSettingsNotifier extends AsyncNotifier<ShoppingSettings> {
  static const _budget = 'shopping_budget';
  static const _dismissed = 'shopping_dismissed';

  @override
  Future<ShoppingSettings> build() async {
    final db = ref.watch(userDatabaseProvider).value;
    if (db == null) return const ShoppingSettings();
    final rows = await db.getAll(
      'SELECT key, value FROM local_settings WHERE key IN (?, ?)',
      [_budget, _dismissed],
    );
    final values = {for (final r in rows) r['key']! as String: r['value']};
    Set<String> dismissed = {};
    try {
      dismissed = {
        for (final k
            in jsonDecode(values[_dismissed] as String? ?? '[]') as List)
          if (k is String) k,
      };
    } on FormatException {
      // Valor estragado: começa vazio.
    }
    return ShoppingSettings(
      budgetEur: int.tryParse(values[_budget] as String? ?? ''),
      dismissed: dismissed,
    );
  }

  Future<void> setBudget(int? euros) async {
    final current = await future;
    await _write(_budget, euros?.toString());
    if (ref.mounted) {
      state = AsyncData(
        ShoppingSettings(budgetEur: euros, dismissed: current.dismissed),
      );
    }
  }

  Future<void> dismiss(String key) async {
    final current = await future;
    final dismissed = {...current.dismissed, key};
    await _write(_dismissed, jsonEncode(dismissed.toList()));
    if (ref.mounted) {
      state = AsyncData(
        ShoppingSettings(budgetEur: current.budgetEur, dismissed: dismissed),
      );
    }
  }

  Future<void> _write(String key, String? value) async {
    final db = ref.read(userDatabaseProvider).value;
    if (db == null) return;
    if (value == null) {
      await db.execute('DELETE FROM local_settings WHERE key = ?', [key]);
    } else {
      await db.execute(
        'INSERT OR REPLACE INTO local_settings (key, value) VALUES (?, ?)',
        [key, value],
      );
    }
  }
}
