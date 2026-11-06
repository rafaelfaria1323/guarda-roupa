import 'package:flutter/material.dart';

/// Visual "fio" (v2, aprovado a 2026-11-05; docs/design-e-fluxos.md):
/// fundo de papel quente, texto quase preto e um só destaque índigo. As cores
/// fortes ficam para as fotos das peças. O modo escuro (2026-11-06) é o
/// mesmo papel à noite: fundo quase preto quente, texto claro e o índigo
/// mais claro para se ler.
@immutable
final class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.background,
    required this.surface,
    required this.surfaceMuted,
    required this.onSurface,
    required this.onSurfaceMuted,
    required this.faint,
    required this.accent,
    required this.onAccent,
    required this.accentSoft,
    required this.onAccentSoft,
    required this.outline,
    required this.divider,
    required this.care,
    required this.onCareSoft,
    required this.shadow,
  });

  static const light = AppColors(
    background: Color(0xFFF3F0EA),
    surface: Color(0xFFFFFFFF),
    surfaceMuted: Color(0xFFEAE6DE),
    onSurface: Color(0xFF1E1F24),
    onSurfaceMuted: Color(0xFF5C5E66),
    faint: Color(0xFF9C9A93),
    accent: Color(0xFF3446C9),
    onAccent: Color(0xFFFFFFFF),
    accentSoft: Color(0xFFECEEF9),
    onAccentSoft: Color(0xFF26349A),
    outline: Color(0xFFD5D0C6),
    divider: Color(0xFFE4DFD5),
    care: Color(0xFFD9822B),
    onCareSoft: Color(0xFF8A4B12),
    shadow: Color(0x2E3C321E),
  );

  static const dark = AppColors(
    background: Color(0xFF151413),
    surface: Color(0xFF211F1D),
    surfaceMuted: Color(0xFF2D2B28),
    onSurface: Color(0xFFEDEAE4),
    onSurfaceMuted: Color(0xFFA9A69F),
    faint: Color(0xFF75726C),
    accent: Color(0xFF9AA6FF),
    onAccent: Color(0xFF111A5C),
    accentSoft: Color(0xFF282E58),
    onAccentSoft: Color(0xFFD0D5FF),
    outline: Color(0xFF45423D),
    divider: Color(0xFF302E2A),
    care: Color(0xFFE99A4E),
    onCareSoft: Color(0xFFF4BC85),
    shadow: Color(0x66000000),
  );

  /// As cores do tema atual.
  static AppColors of(BuildContext context) =>
      Theme.of(context).extension<AppColors>() ?? light;

  final Color background;
  final Color surface;
  final Color surfaceMuted;
  final Color onSurface;
  final Color onSurfaceMuted;

  /// Texto e traços apagados (ex.: dias passados no fio da semana).
  final Color faint;
  final Color accent;
  final Color onAccent;
  final Color accentSoft;
  final Color onAccentSoft;
  final Color outline;
  final Color divider;

  /// Estados de lavandaria ("a lavar", "a secar").
  final Color care;
  final Color onCareSoft;

  /// Sombra das miniaturas das peças.
  final Color shadow;

  /// Texto sobre [onSurface] (chips e botões escolhidos).
  Color get onInverse => this == dark ? background : surface;

  @override
  AppColors copyWith() => this;

  @override
  AppColors lerp(AppColors? other, double t) =>
      other == null || t < 0.5 ? this : other;
}

/// Texto do corpo e da interface.
const bodyFont = 'DMSans';

/// Títulos (só tamanhos grandes: a Fraunces é de display).
const displayFont = 'Fraunces';

ThemeData buildAppTheme([Brightness brightness = Brightness.light]) {
  final c = brightness == Brightness.dark ? AppColors.dark : AppColors.light;
  final scheme = ColorScheme.fromSeed(
    brightness: brightness,
    seedColor: c.accent,
    primary: c.accent,
    onPrimary: c.onAccent,
    primaryContainer: c.accentSoft,
    onPrimaryContainer: c.onAccentSoft,
    secondaryContainer: c.accentSoft,
    onSecondaryContainer: c.onAccentSoft,
    surface: c.background,
    onSurface: c.onSurface,
    onSurfaceVariant: c.onSurfaceMuted,
    surfaceContainerLowest: c.surface,
    surfaceContainerLow: c.surface,
    surfaceContainer: c.surface,
    surfaceContainerHigh: c.surface,
    surfaceContainerHighest: c.surfaceMuted,
    outline: c.outline,
    outlineVariant: c.divider,
    inverseSurface: c.onSurface,
    onInverseSurface: c.onInverse,
  );

  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: bodyFont,
  ).textTheme;
  TextStyle display(TextStyle? s, double size) => s!.copyWith(
    fontFamily: displayFont,
    fontSize: size,
    fontWeight: FontWeight.w500,
    letterSpacing: -0.4,
    height: 1.1,
    color: c.onSurface,
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
    brightness: brightness,
    extensions: [c],
    colorScheme: scheme,
    fontFamily: bodyFont,
    textTheme: text,
    scaffoldBackgroundColor: c.background,
    dividerTheme: DividerThemeData(color: c.divider, space: 1),
    appBarTheme: AppBarTheme(
      backgroundColor: c.background,
      foregroundColor: c.onSurface,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: display(base.headlineSmall, 26),
    ),
    cardTheme: CardThemeData(
      color: c.surface,
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
        padding: EdgeInsets.symmetric(horizontal: 24),
        textStyle: buttonText,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        shape: pill,
        minimumSize: buttonSize,
        elevation: 0,
        backgroundColor: c.accent,
        foregroundColor: c.onAccent,
        textStyle: buttonText,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: pill,
        minimumSize: buttonSize,
        foregroundColor: c.onSurface,
        side: BorderSide(color: c.outline),
        textStyle: buttonText,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: pill,
        minimumSize: Size(48, 44),
        foregroundColor: c.onSurface,
        textStyle: buttonText.copyWith(
          decoration: TextDecoration.underline,
          decorationColor: c.outline,
        ),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: c.onSurface),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: c.accent,
      foregroundColor: c.onAccent,
      elevation: 2,
      highlightElevation: 4,
      shape: StadiumBorder(),
    ),
    chipTheme: ChipThemeData(
      shape: pill,
      side: BorderSide(color: c.outline),
      backgroundColor: Colors.transparent,
      selectedColor: c.onSurface,
      checkmarkColor: c.onInverse,
      // A cor segue o estado: em FilterChip o rótulo selecionado não usa
      // secondaryLabelStyle e ficaria preto sobre preto.
      labelStyle: text.labelMedium!.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: WidgetStateColor.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? c.onInverse
              : states.contains(WidgetState.disabled)
              ? c.onSurfaceMuted
              : c.onSurface,
        ),
      ),
      secondaryLabelStyle: text.labelMedium!.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: c.onInverse,
      ),
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        shape: pill,
        side: BorderSide(color: c.outline),
        selectedBackgroundColor: c.onSurface,
        selectedForegroundColor: c.onInverse,
        foregroundColor: c.onSurface,
        textStyle: text.labelLarge,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.surface,
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
        borderSide: BorderSide(color: c.accent, width: 1.5),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      height: 68,
      indicatorColor: c.accentSoft,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => text.labelMedium!.copyWith(
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w600,
          color: states.contains(WidgetState.selected)
              ? c.accent
              : c.onSurfaceMuted,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? c.accent
              : c.onSurfaceMuted,
        ),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: c.background,
      indicatorColor: c.accentSoft,
      selectedIconTheme: IconThemeData(color: c.accent),
    ),
    listTileTheme: ListTileThemeData(iconColor: c.onSurfaceMuted),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: c.onSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.background,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.background,
      surfaceTintColor: Colors.transparent,
    ),
  );
}
