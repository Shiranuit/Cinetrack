import 'package:flutter/material.dart';

/// Brand palette — "midnight cinema": deep blue-black surfaces lit by a warm
/// amber-gold marquee accent, with rose for favorites and mint for watched.
/// Deliberately NOT a generic purple-on-white scheme.
class Brand {
  Brand._();
  static const Color primary = Color(0xFFF4B740); // amber gold — marquee lights
  static const Color seen = Color(0xFF48DE9C); // watched / progress mint
  static const Color favorite = Color(0xFFFF5D73); // favorite rose
  static const Color warning = Color(0xFFFFC24B); // stale / attention

  // Dark surfaces — near-black with a cool blue undertone, layered.
  static const Color darkBg = Color(0xFF090A0F);
  static const Color darkSurface = Color(0xFF14161F);
  static const Color darkSurfaceHigh = Color(0xFF1D2130);
  static const Color darkPosterBg = Color(0xFF222634);

  // Light surfaces — warm paper, not stark white.
  static const Color lightBg = Color(0xFFF4F1EA);
  static const Color lightSurface = Color(0xFFFFFDF9);
  static const Color lightSurfaceHigh = Color(0xFFEBE6DB);
  static const Color lightPosterBg = Color(0xFFE0DBCF);
}

/// Semantic colors that aren't part of Material's [ColorScheme] but must stay
/// consistent across the app. Exposed via a [ThemeExtension] so components read
/// `context.colors.seen` etc. and automatically adapt to light/dark.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  final Color seen;
  final Color favorite;
  final Color warning;
  final Color posterBg;
  final Color scrim;

  const AppColors({
    required this.seen,
    required this.favorite,
    required this.warning,
    required this.posterBg,
    required this.scrim,
  });

  static const dark = AppColors(
    seen: Brand.seen,
    favorite: Brand.favorite,
    warning: Brand.warning,
    posterBg: Brand.darkPosterBg,
    scrim: Color(0xE6090A0F),
  );

  static const light = AppColors(
    seen: Color(0xFF12A870),
    favorite: Color(0xFFE23D74),
    warning: Color(0xFFB8791A),
    posterBg: Brand.lightPosterBg,
    scrim: Color(0x99000000),
  );

  @override
  AppColors copyWith({Color? seen, Color? favorite, Color? warning, Color? posterBg, Color? scrim}) =>
      AppColors(
        seen: seen ?? this.seen,
        favorite: favorite ?? this.favorite,
        warning: warning ?? this.warning,
        posterBg: posterBg ?? this.posterBg,
        scrim: scrim ?? this.scrim,
      );

  @override
  AppColors lerp(AppColors? other, double t) {
    if (other == null) return this;
    return AppColors(
      seen: Color.lerp(seen, other.seen, t)!,
      favorite: Color.lerp(favorite, other.favorite, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      posterBg: Color.lerp(posterBg, other.posterBg, t)!,
      scrim: Color.lerp(scrim, other.scrim, t)!,
    );
  }
}

/// Ergonomic accessors: `context.colors.seen`, `context.scheme.primary`,
/// `context.text.titleLarge`.
extension ThemeAccessX on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
  ColorScheme get scheme => Theme.of(this).colorScheme;
  TextTheme get text => Theme.of(this).textTheme;
}
