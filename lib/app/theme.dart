import 'package:flutter/material.dart';

/// Visual "fio" (v2, aprovado a 2026-11-05; docs/design-e-fluxos.md):
/// fundo de papel quente, texto quase preto e um só destaque índigo. As cores
/// fortes ficam para as fotos das peças.
abstract final class AppColors {
  static const background = Color(0xFFF3F0EA);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceMuted = Color(0xFFEAE6DE);
  static const onSurface = Color(0xFF1E1F24);
  static const onSurfaceMuted = Color(0xFF5C5E66);
  static const accent = Color(0xFF3446C9);
  static const accentSoft = Color(0xFFECEEF9);
  static const onAccentSoft = Color(0xFF26349A);
  static const outline = Color(0xFFD5D0C6);
  static const divider = Color(0xFFE4DFD5);

  /// Estados de lavandaria ("a lavar", "a secar").
  static const care = Color(0xFFD9822B);
  static const onCareSoft = Color(0xFF8A4B12);
}

/// Texto do corpo e da interface.
const bodyFont = 'DMSans';

/// Títulos (só tamanhos grandes: a Fraunces é de display).
const displayFont = 'Fraunces';

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.accent,
    primary: AppColors.accent,
    onPrimary: Colors.white,
    primaryContainer: AppColors.accentSoft,
    onPrimaryContainer: AppColors.onAccentSoft,
    secondaryContainer: AppColors.accentSoft,
    onSecondaryContainer: AppColors.onAccentSoft,
    surface: AppColors.background,
    onSurface: AppColors.onSurface,
    onSurfaceVariant: AppColors.onSurfaceMuted,
    surfaceContainerLowest: AppColors.surface,
    surfaceContainerLow: AppColors.surface,
    surfaceContainer: AppColors.surface,
    surfaceContainerHigh: AppColors.surface,
    surfaceContainerHighest: AppColors.surfaceMuted,
    outline: AppColors.outline,
    outlineVariant: AppColors.divider,
  );

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: bodyFont,
  ).textTheme;
  TextStyle display(TextStyle? s, double size) => s!.copyWith(
    fontFamily: displayFont,
    fontSize: size,
    fontWeight: FontWeight.w500,
    letterSpacing: -0.4,
    height: 1.1,
    color: AppColors.onSurface,
  );
  final text = base.copyWith(
    displaySmall: display(base.displaySmall, 36),
    headlineLarge: display(base.headlineLarge, 32),
    headlineMedium: display(base.headlineMedium, 28),
    headlineSmall: display(base.headlineSmall, 24),
    titleLarge: display(base.titleLarge, 21),
    titleMedium: base.titleMedium!.copyWith(fontWeight: FontWeight.w700),
    titleSmall: base.titleSmall!.copyWith(fontWeight: FontWeight.w700),
    labelLarge: base.labelLarge!.copyWith(
      fontWeight: FontWeight.w600,
      fontSize: 15,
    ),
  );

  const pill = StadiumBorder();
  const buttonSize = Size(64, 48);
  final buttonText = text.labelLarge!.copyWith(fontWeight: FontWeight.w700);

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: bodyFont,
    textTheme: text,
    scaffoldBackgroundColor: AppColors.background,
    dividerTheme: const DividerThemeData(color: AppColors.divider, space: 1),
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.background,
      foregroundColor: AppColors.onSurface,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: display(base.headlineSmall, 26),
    ),
    cardTheme: const CardThemeData(
      color: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(24)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: pill,
        minimumSize: buttonSize,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        textStyle: buttonText,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        shape: pill,
        minimumSize: buttonSize,
        elevation: 0,
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.white,
        textStyle: buttonText,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: pill,
        minimumSize: buttonSize,
        foregroundColor: AppColors.onSurface,
        side: const BorderSide(color: AppColors.outline),
        textStyle: buttonText,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: pill,
        minimumSize: const Size(48, 44),
        foregroundColor: AppColors.onSurface,
        textStyle: buttonText.copyWith(
          decoration: TextDecoration.underline,
          decorationColor: AppColors.outline,
        ),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: AppColors.onSurface),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.accent,
      foregroundColor: Colors.white,
      elevation: 2,
      highlightElevation: 4,
      shape: StadiumBorder(),
    ),
    chipTheme: ChipThemeData(
      shape: pill,
      side: const BorderSide(color: AppColors.outline),
      backgroundColor: Colors.transparent,
      selectedColor: AppColors.onSurface,
      checkmarkColor: Colors.white,
      // A cor segue o estado: em FilterChip o rótulo selecionado não usa
      // secondaryLabelStyle e ficaria preto sobre preto.
      labelStyle: text.labelMedium!.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: WidgetStateColor.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.white
              : states.contains(WidgetState.disabled)
              ? AppColors.onSurfaceMuted
              : AppColors.onSurface,
        ),
      ),
      secondaryLabelStyle: text.labelMedium!.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: Colors.white,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        shape: pill,
        side: const BorderSide(color: AppColors.outline),
        selectedBackgroundColor: AppColors.onSurface,
        selectedForegroundColor: Colors.white,
        foregroundColor: AppColors.onSurface,
        textStyle: text.labelLarge,
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
        borderSide: BorderSide(color: AppColors.accent, width: 1.5),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      height: 68,
      indicatorColor: AppColors.accentSoft,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => text.labelMedium!.copyWith(
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w600,
          color: states.contains(WidgetState.selected)
              ? AppColors.accent
              : AppColors.onSurfaceMuted,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? AppColors.accent
              : AppColors.onSurfaceMuted,
        ),
      ),
    ),
    navigationRailTheme: const NavigationRailThemeData(
      backgroundColor: AppColors.background,
      indicatorColor: AppColors.accentSoft,
      selectedIconTheme: IconThemeData(color: AppColors.accent),
    ),
    listTileTheme: const ListTileThemeData(iconColor: AppColors.onSurfaceMuted),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.onSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.background,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: AppColors.background,
      surfaceTintColor: Colors.transparent,
    ),
  );
}
