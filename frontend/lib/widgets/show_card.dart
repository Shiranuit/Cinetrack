import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../design/app_colors.dart';
import '../design/tokens.dart';
import 'badges.dart';
import 'poster.dart';

/// Height reserved for a card's caption (title + optional subtitle). Fixed so
/// cards never overflow their rail/grid cell.
const double kCardCaptionHeight = 44;

/// The canonical show/movie tile: poster + title (+ optional subtitle, favorite
/// heart, progress). Used in rails and grids.
class ShowCard extends StatelessWidget {
  const ShowCard({
    super.key,
    required this.title,
    this.imageUrl,
    this.onTap,
    this.onLongPress,
    this.subtitle,
    this.favorite = false,
    this.progress = 0,
    this.heroTag,
  });

  final String title;
  final String? imageUrl;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final String? subtitle;
  final bool favorite;
  final double progress;
  final Object? heroTag;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      // On web a mouse press+drag on a card would otherwise get caught by the
      // long-press recognizer (opening the context sheet) and starve the rail's
      // horizontal drag — so a drag "acts like a right-click" and the carousel
      // won't scroll. Drop long-press on web and expose the same menu via a real
      // right-click (secondary tap), which is the correct desktop idiom anyway.
      onLongPress: kIsWeb ? null : onLongPress,
      onSecondaryTap: onLongPress,
      borderRadius: BorderRadius.circular(Radii.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Poster(
            url: imageUrl,
            heroTag: heroTag,
            overlay: Stack(
              fit: StackFit.expand,
              children: [
                if (favorite)
                  Positioned(
                    top: Insets.xs,
                    right: Insets.xs,
                    child: Icon(Icons.favorite, size: 18, color: context.colors.favorite),
                  ),
                ProgressStripe(value: progress),
              ],
            ),
          ),
          const SizedBox(height: Insets.sm),
          SizedBox(
            height: kCardCaptionHeight,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: subtitle == null ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w600, height: 1.15),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.labelSmall?.copyWith(color: context.scheme.onSurfaceVariant),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
