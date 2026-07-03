import 'package:flutter/material.dart';

import '../design/app_colors.dart';
import '../design/tokens.dart';

/// A circular "×N watched" badge: filled green with the count when seen, an
/// outlined eye when unseen. Fixed circular shape for a consistent control.
class CountBadge extends StatelessWidget {
  const CountBadge({super.key, required this.count, this.size = 38});
  final int count;
  final double size;

  @override
  Widget build(BuildContext context) {
    final seen = count > 0;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: seen ? context.colors.seen : Colors.transparent,
        border: seen ? null : Border.all(color: context.scheme.onSurfaceVariant.withValues(alpha: 0.5), width: 1.5),
      ),
      child: seen
          ? Text('×$count', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13))
          : Icon(Icons.visibility_outlined, size: 18, color: context.scheme.onSurfaceVariant),
    );
  }
}

/// Watched control: a circular badge (tap to watch / rewatch) with a matching
/// circular minus button to the left once watched. Both round → consistent.
class WatchControl extends StatelessWidget {
  const WatchControl({super.key, required this.count, required this.onWatch, required this.onUnwatch, this.size = 38});
  final int count;
  final VoidCallback onWatch;
  final VoidCallback onUnwatch;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (count > 0) ...[
          _RoundButton(icon: Icons.remove_rounded, onTap: onUnwatch, size: size),
          const SizedBox(width: Insets.sm),
        ],
        Tooltip(
          message: count > 0 ? 'Mark watched again' : 'Mark watched',
          child: InkResponse(onTap: onWatch, radius: size / 2, child: CountBadge(count: count, size: size)),
        ),
      ],
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.onTap, required this.size});
  final IconData icon;
  final VoidCallback onTap;
  final double size;
  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      radius: size / 2,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: context.scheme.onSurfaceVariant.withValues(alpha: 0.5), width: 1.5),
        ),
        child: Icon(icon, size: 18, color: context.scheme.onSurfaceVariant),
      ),
    );
  }
}

/// A thin progress bar overlaid at the bottom of a poster (0..1).
class ProgressStripe extends StatelessWidget {
  const ProgressStripe({super.key, required this.value});
  final double value;

  @override
  Widget build(BuildContext context) {
    if (value <= 0) return const SizedBox.shrink();
    // A thin, subtle bar hugging the poster's bottom edge (clipped to its rounded
    // corners by the parent), showing how much of the show has been seen.
    return Align(
      alignment: Alignment.bottomCenter,
      child: LinearProgressIndicator(
        value: value.clamp(0, 1),
        minHeight: 3,
        backgroundColor: Colors.black.withValues(alpha: 0.35),
        valueColor: AlwaysStoppedAnimation(context.colors.seen),
      ),
    );
  }
}

/// A rounded status pill (e.g. "For later", "Continuing").
class Pill extends StatelessWidget {
  const Pill({super.key, required this.label, this.color, this.icon});
  final String label;
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.scheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Insets.sm, vertical: 3),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(Radii.pill)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 13, color: c), const SizedBox(width: 4)],
          Text(label, style: TextStyle(color: c, fontWeight: FontWeight.w700, fontSize: 11)),
        ],
      ),
    );
  }
}
