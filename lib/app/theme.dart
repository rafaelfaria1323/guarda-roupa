import 'package:flutter/material.dart';

/// Tokens propostos em docs/design-e-fluxos.md (ainda sujeitos a validação
/// de contraste e aprovação).
abstract final class AppColors {
  static const background = Color(0xFFF6F4EF);
  static const surface = Color(0xFFFFFFFF);
  static const onSurface = Color(0xFF202521);
  static const accent = Color(0xFF61745B);
  static const divider = Color(0xFFDFE3DC);
}

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.accent,
    primary: AppColors.accent,
    surface: AppColors.surface,
    onSurface: AppColors.onSurface,
    outlineVariant: AppColors.divider,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.background,
    dividerTheme: const DividerThemeData(color: AppColors.divider),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.background,
      foregroundColor: AppColors.onSurface,
      scrolledUnderElevation: 0,
    ),
  );
}
