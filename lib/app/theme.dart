import 'package:flutter/material.dart';

/// Visual "fio" (v3, 2026-11-06, do design do Stitch; docs/design-e-fluxos.md):
/// linho quente, cartões brancos com contorno fino e um só destaque verde
/// salva. As cores fortes ficam para as fotos das peças. O escuro é o mesmo
/// à noite: verde-carvão, texto marfim e o salva mais claro para se ler.
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
    background: Color(0xFFFBF9F2),
    surface: Color(0xFFFFFFFF),
    surfaceMuted: Color(0xFFEFEEE7),
    onSurface: Color(0xFF1B1C18),
    onSurfaceMuted: Color(0xFF5B5F57),
    faint: Color(0xFF9A9C93),
    accent: Color(0xFF51604B),
    onAccent: Color(0xFFFFFFFF),
    accentSoft: Color(0xFFE2ECDA),
    onAccentSoft: Color(0xFF3C4B37),
    outline: Color(0xFFD9D6CC),
    divider: Color(0xFFECE7DE),
    care: Color(0xFFD9A78F),
    onCareSoft: Color(0xFF7D5541),
    shadow: Color(0x24393A35),
  );

  static const dark = AppColors(
    background: Color(0xFF111410),
    surface: Color(0xFF1D201C),
    surfaceMuted: Color(0xFF282B27),
    onSurface: Color(0xFFE6E8E1),
    onSurfaceMuted: Color(0xFFB4B7AC),
    faint: Color(0xFF7D8077),
    accent: Color(0xFFBCCCAC),
    onAccent: Color(0xFF27341E),
    accentSoft: Color(0xFF3D4737),
    onAccentSoft: Color(0xFFD8E8C7),
    outline: Color(0xFF454840),
    divider: Color(0xFF2C2F2A),
    care: Color(0xFFEFBBA2),
    onCareSoft: Color(0xFFEFBBA2),
    shadow: Color(0x730E100D),
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
const bodyFont = 'Manrope';

/// Títulos: a mesma Manrope, mais cheia e mais apertada.
const displayFont = bodyFont;

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
    fontWeight: size >= 24 ? FontWeight.w700 : FontWeight.w600,
    letterSpacing: -0.02 * size,
    height: 1.2,
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
      titleTextStyle: display(base.headlineSmall, 22),
    ),
    cardTheme: CardThemeData(
      color: c.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
        side: BorderSide(color: c.divider),
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
      backgroundColor: c.surface,
      selectedColor: c.accent,
      checkmarkColor: c.onAccent,
      // A cor segue o estado: em FilterChip o rótulo selecionado não usa
      // secondaryLabelStyle e ficaria preto sobre preto.
      labelStyle: text.labelMedium!.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: WidgetStateColor.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? c.onAccent
              : states.contains(WidgetState.disabled)
              ? c.onSurfaceMuted
              : c.onSurface,
        ),
      ),
      secondaryLabelStyle: text.labelMedium!.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: c.onAccent,
      ),
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        shape: pill,
        side: BorderSide(color: c.outline),
        selectedBackgroundColor: c.accent,
        selectedForegroundColor: c.onAccent,
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
        borderSide: BorderSide(color: c.divider),
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
