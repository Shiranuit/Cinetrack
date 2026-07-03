import 'package:flutter/widgets.dart';

/// Design tokens — the single source of truth for spacing, shape, motion and
/// layout breakpoints. Components and screens must use these instead of magic
/// numbers so the UI stays consistent.

/// 4pt spacing scale.
class Insets {
  Insets._();
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;

  static const EdgeInsets pageH = EdgeInsets.symmetric(horizontal: lg);
  static const EdgeInsets page = EdgeInsets.all(lg);
}

/// Corner radii.
class Radii {
  Radii._();
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double pill = 999;

  static const BorderRadius card = BorderRadius.all(Radius.circular(md));
  static const BorderRadius poster = BorderRadius.all(Radius.circular(md));
  static const BorderRadius sheet = BorderRadius.vertical(top: Radius.circular(xl));
}

/// Motion durations + curves.
class Motion {
  Motion._();
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration medium = Duration(milliseconds: 260);
  static const Curve curve = Curves.easeOutCubic;
}

/// Responsive breakpoints (Material 3 window size classes).
class Breakpoints {
  Breakpoints._();
  static const double compact = 600; // phones
  static const double medium = 900; // small tablets / split
  static const double expanded = 1200; // desktop

  static bool isCompact(double w) => w < compact;
  static bool isExpanded(double w) => w >= expanded;

  /// Number of poster columns for a grid at the given width.
  static int posterColumns(double w) {
    if (w >= 1500) return 8;
    if (w >= expanded) return 7;
    if (w >= medium) return 5;
    if (w >= compact) return 4;
    return 3;
  }
}

/// Poster aspect ratio (width : height) used everywhere for artwork.
const double kPosterAspect = 2 / 3;
