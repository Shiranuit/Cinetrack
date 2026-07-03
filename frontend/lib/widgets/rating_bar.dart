import 'package:flutter/material.dart';

import '../design/app_colors.dart';

/// A 1–10 star rating control. Tapping a star sets that rating; tapping the
/// current rating again clears it (calls `onRate(null)`). Scales down to fit.
class RatingBar extends StatelessWidget {
  const RatingBar({super.key, required this.value, required this.onRate, this.size = 26});
  final int? value; // 1..10, null = unrated
  final void Function(int? rating) onRate;
  final double size;

  @override
  Widget build(BuildContext context) {
    final v = value ?? 0;
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 1; i <= 10; i++)
            IconButton(
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              constraints: BoxConstraints.tightFor(width: size + 2, height: size + 4),
              iconSize: size,
              tooltip: '$i',
              icon: Icon(
                i <= v ? Icons.star_rounded : Icons.star_border_rounded,
                color: i <= v ? context.colors.warning : context.scheme.onSurfaceVariant,
              ),
              onPressed: () => onRate(i == value ? null : i),
            ),
        ],
      ),
    );
  }
}
