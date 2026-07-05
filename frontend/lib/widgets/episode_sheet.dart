import 'package:flutter/material.dart';

import '../api/models.dart';
import '../design/app_colors.dart';
import '../design/tokens.dart';
import 'badges.dart';
import 'net_image.dart';

/// The rich episode bottom sheet: a 16:9 still, S·E label with a watch control,
/// the episode title, air date and overview. Shared by the show detail episode
/// list and the calendar so tapping an episode looks the same everywhere.
class EpisodeSheet extends StatelessWidget {
  const EpisodeSheet({
    super.key,
    required this.episode,
    required this.count,
    required this.onWatch,
    required this.onUnwatch,
    this.showImageUrl,
    this.showName,
    this.onOpenShow,
  });
  final Episode episode;
  final int count;
  final VoidCallback onWatch;
  final VoidCallback onUnwatch;

  /// Series artwork, used as the still when the episode has no image of its own.
  final String? showImageUrl;

  /// The show's name, shown as a header above the still. Tapping it calls
  /// [onOpenShow] (when set) to open the full show page.
  final String? showName;
  final VoidCallback? onOpenShow;

  @override
  Widget build(BuildContext context) {
    final image = (episode.imageUrl?.isNotEmpty ?? false) ? episode.imageUrl : showImageUrl;
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showName != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(Insets.lg, 0, Insets.lg, Insets.sm),
                child: InkWell(
                  onTap: onOpenShow,
                  borderRadius: BorderRadius.circular(Radii.sm),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: Insets.xs),
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(showName!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                        ),
                        if (onOpenShow != null) ...[
                          const SizedBox(width: 4),
                          Icon(Icons.chevron_right_rounded, size: 20, color: context.scheme.onSurfaceVariant),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Insets.lg),
              child: ClipRRect(
                borderRadius: Radii.card,
                child: AspectRatio(aspectRatio: 16 / 9, child: NetImage(url: image)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(Insets.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'S${episode.seasonNumber ?? 0} · E${episode.number ?? 0}',
                          style: context.text.labelLarge?.copyWith(color: context.scheme.primary),
                        ),
                      ),
                      WatchControl(count: count, onWatch: onWatch, onUnwatch: onUnwatch, size: 44),
                    ],
                  ),
                  const SizedBox(height: Insets.xs),
                  Text(episode.name ?? '', style: context.text.titleLarge),
                  if (episode.aired != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(episode.aired!,
                          style: context.text.labelMedium?.copyWith(color: context.scheme.onSurfaceVariant)),
                    ),
                  if (episode.overview?.isNotEmpty ?? false) ...[
                    const SizedBox(height: Insets.md),
                    Text(episode.overview!, style: context.text.bodyMedium?.copyWith(height: 1.5)),
                  ],
                  const SizedBox(height: Insets.md),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
