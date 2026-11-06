import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../account_sync/application/providers.dart';
import '../domain/photo_reader.dart';

/// Leitor de fotos do servidor; `null` sem Supabase (testes, modo local).
final photoReaderProvider = Provider<PhotoReader?>((ref) => null);

/// O utilizador ligou "Ler fotos com o Gemini" neste dispositivo. Desligado
/// de início (a foto sai do aparelho). `null` enquanto a base local abre.
final geminiPhotosProvider = AsyncNotifierProvider<GeminiPhotos, bool?>(
  GeminiPhotos.new,
);

class GeminiPhotos extends AsyncNotifier<bool?> {
  static const _key = 'gemini_photos';

  @override
  Future<bool?> build() async {
    final db = ref.watch(userDatabaseProvider).value;
    if (db == null) return null;
    final row = await db.getOptional(
      'SELECT value FROM local_settings WHERE key = ?',
      [_key],
    );
    return row?['value'] == '1';
  }

  Future<void> set({required bool enabled}) async {
    final db = ref.read(userDatabaseProvider).value;
    if (db == null) return;
    await db.execute(
      'INSERT OR REPLACE INTO local_settings (key, value) VALUES (?, ?)',
      [_key, enabled ? '1' : '0'],
    );
    if (ref.mounted) state = AsyncData(enabled);
  }
}

/// O leitor, só com a opção ligada; senão `null` e a app usa o que tem
/// neste dispositivo.
final activePhotoReaderProvider = Provider<PhotoReader?>((ref) {
  final reader = ref.watch(photoReaderProvider);
  if (reader == null) return null;
  return ref.watch(geminiPhotosProvider).value == true ? reader : null;
});
