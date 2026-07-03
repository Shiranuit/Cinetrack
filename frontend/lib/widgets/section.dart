import 'package:flutter/material.dart';

import '../design/app_colors.dart';
import '../design/tokens.dart';
import 'show_card.dart';

/// A section title, optionally with a leading accent dot/icon and a trailing count.
class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.icon, this.accent, this.trailing});
  final String title;
  final IconData? icon;
  final Color? accent;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = accent ?? context.scheme.primary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Insets.lg, Insets.lg, Insets.lg, Insets.sm),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 20, color: c),
            const SizedBox(width: Insets.sm),
          ] else ...[
            Container(width: 4, height: 18, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: Insets.sm),
          ],
          Expanded(child: Text(title, style: context.text.titleMedium)),
          ?trailing,
        ],
      ),
    );
  }
}

/// A horizontally-scrolling rail of fixed-width cards under a [SectionHeader].
class PosterRail extends StatelessWidget {
  const PosterRail({
    super.key,
    required this.title,
    required this.count,
    required this.itemBuilder,
    this.icon,
    this.accent,
    this.cardWidth = 118,
    this.onSeeAll,
  });

  final String title;
  final IconData? icon;
  final Color? accent;
  final int count;
  final double cardWidth;
  final Widget Function(BuildContext, int) itemBuilder;
  /// When set, shows a "See all" action in the header instead of just the count.
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    if (count == 0) return const SizedBox.shrink();
    final railHeight = cardWidth / kPosterAspect + Insets.sm + kCardCaptionHeight;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: title,
          icon: icon,
          accent: accent,
          trailing: onSeeAll != null
              ? TextButton(
                  onPressed: onSeeAll,
                  style: TextButton.styleFrom(
                    minimumSize: Size.zero,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('See all'))
              : Text('$count', style: context.text.labelMedium?.copyWith(color: context.scheme.onSurfaceVariant)),
        ),
        SizedBox(
          height: railHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: Insets.pageH,
            itemCount: count,
            separatorBuilder: (_, _) => const SizedBox(width: Insets.md),
            itemBuilder: (context, i) => SizedBox(width: cardWidth, child: itemBuilder(context, i)),
          ),
        ),
      ],
    );
  }
}
