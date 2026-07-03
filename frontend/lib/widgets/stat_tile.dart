import 'package:flutter/material.dart';

import '../design/app_colors.dart';
import '../design/tokens.dart';

/// A compact profile stat: big value + label with an accent icon.
class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.value, required this.label, required this.icon, this.accent});
  final String value;
  final String label;
  final IconData icon;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final c = accent ?? context.scheme.primary;
    return Container(
      padding: const EdgeInsets.all(Insets.lg),
      decoration: BoxDecoration(color: context.scheme.surface, borderRadius: Radii.card),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: c),
          const SizedBox(height: Insets.md),
          Text(value, style: context.text.headlineSmall),
          const SizedBox(height: 2),
          Text(label, style: context.text.labelMedium?.copyWith(color: context.scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}
