import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';
import 'tokens.dart';

/// Builds the light and dark [ThemeData] from the design tokens. This is the
/// only place that assembles Material theming; screens never set raw colors.
///
/// Type pairing: **Bricolage Grotesque** (characterful display) for titles and
/// numbers, **DM Sans** (clean, refined) for body/labels.
class AppTheme {
  AppTheme._();

  static ThemeData dark() => _build(Brightness.dark);
  static ThemeData light() => _build(Brightness.light);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: Brand.primary,
      brightness: brightness,
    ).copyWith(
      primary: Brand.primary,
      onPrimary: const Color(0xFF2A1E00),
      surface: isDark ? Brand.darkSurface : Brand.lightSurface,
      surfaceContainerHighest: isDark ? Brand.darkSurfaceHigh : Brand.lightSurfaceHigh,
    );
    final bg = isDark ? Brand.darkBg : Brand.lightBg;
    final appColors = isDark ? AppColors.dark : AppColors.light;

    final base = ThemeData(brightness: brightness, useMaterial3: true, colorScheme: scheme);
    final text = _typography(base.textTheme);

    return base.copyWith(
      scaffoldBackgroundColor: bg,
      textTheme: text,
      extensions: [appColors],
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: const RoundedRectangleBorder(borderRadius: Radii.card),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: (isDark ? Brand.darkSurface : Brand.lightSurface).withValues(alpha: 0.92),
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primary.withValues(alpha: 0.20),
        elevation: 0,
        height: 66,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStatePropertyAll(text.labelMedium),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected) ? scheme.primary : scheme.onSurfaceVariant,
          ),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: scheme.surfaceContainerHighest,
        side: BorderSide.none,
        shape: const StadiumBorder(),
        labelStyle: text.labelMedium,
        padding: const EdgeInsets.symmetric(horizontal: Insets.md, vertical: 2),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest,
        border: const OutlineInputBorder(borderRadius: Radii.card, borderSide: BorderSide.none),
        enabledBorder: const OutlineInputBorder(borderRadius: Radii.card, borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: Radii.card,
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: Insets.lg, vertical: Insets.md),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: const RoundedRectangleBorder(borderRadius: Radii.card),
          textStyle: text.titleMedium,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.4),
        space: Insets.lg,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        shape: const RoundedRectangleBorder(borderRadius: Radii.card),
      ),
    );
  }

  static TextTheme _typography(TextTheme base) {
    final body = GoogleFonts.dmSansTextTheme(base);
    final display = GoogleFonts.bricolageGrotesque().fontFamily;
    TextStyle? disp(TextStyle? s, {double spacing = -0.5}) =>
        s?.copyWith(fontFamily: display, fontWeight: FontWeight.w700, letterSpacing: spacing);
    return body.copyWith(
      displaySmall: disp(body.displaySmall),
      headlineLarge: disp(body.headlineLarge),
      headlineMedium: disp(body.headlineMedium),
      headlineSmall: disp(body.headlineSmall, spacing: -0.3),
      titleLarge: disp(body.titleLarge, spacing: -0.2),
      titleMedium: body.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      labelLarge: body.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      labelMedium: body.labelMedium?.copyWith(fontWeight: FontWeight.w600),
    );
  }
}
