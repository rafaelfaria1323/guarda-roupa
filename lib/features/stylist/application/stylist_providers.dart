import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../photo_ai/application/photo_ai_providers.dart';
import '../domain/stylist.dart';

/// Stylist do servidor; `null` sem Supabase (testes, modo local).
final stylistProvider = Provider<Stylist?>((ref) => null);

/// Só com "Usar o Gemini neste aparelho" ligado.
final activeStylistProvider = Provider<Stylist?>((ref) {
  final stylist = ref.watch(stylistProvider);
  if (stylist == null) return null;
  return ref.watch(geminiPhotosProvider).value == true ? stylist : null;
});
