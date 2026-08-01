import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api/models.dart';
import '../design/app_colors.dart';
import '../design/tokens.dart';
import '../l10n/app_localizations.dart';
import 'poster.dart';

/// Poster width in an activity row — small enough that a row stays compact, but
/// still recognizable artwork.
const double _kThumbWidth = 44;

/// A relative "when" label for a unix timestamp: "Just now" under a minute, then
/// m/h/d, and an absolute date past a week (a precise date reads better than
/// "37d ago"). Localized through [AppLocalizations].
String activityWhen(BuildContext context, int? epochSeconds) {
  final t = AppLocalizations.of(context);
  if (epochSeconds == null) return '';
  final when = DateTime.fromMillisecondsSinceEpoch(epochSeconds * 1000);
  final diff = DateTime.now().difference(when);
  // A clock skew between client and server can make a fresh watch look "future";
  // treat anything not yet in the past as just now rather than a negative age.
  if (diff.inMinutes < 1) return t.justNow;
  if (diff.inHours < 1) return t.minutesAgo(diff.inMinutes);
  if (diff.inDays < 1) return t.hoursAgo(diff.inHours);
  if (diff.inDays < 7) return t.daysAgo(diff.inDays);
  return DateFormat.yMMMd(Localizations.localeOf(context).toString()).format(when);
}

/// One entry in an activity timeline: the artwork, what was watched, and when.
/// Presentation only — the hosting screen supplies [onTap] (navigation lives in
/// screens, see `openActivityItem`).
class ActivityTile extends StatelessWidget {
  const ActivityTile({super.key, required this.item, this.onTap});

  final ActivityItem item;
  final VoidCallback? onTap;

  /// "S4E12" — null when neither number is known (so the line is dropped).
  String? get _epTag {
    final s = item.seasonNumber, e = item.episodeNumber;
    if (s == null && e == null) return null;
    return 'S${s ?? '?'}E${e ?? '?'}';
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final title = item.name ??
        (item.isMovie
            ? t.movieFallback(item.movieId ?? 0)
            : t.seriesFallback(item.seriesId ?? 0));
    // Episodes get "S4E12 · Title"; movies have no such line.
    final detail = item.isMovie
        ? null
        : [?_epTag, ?item.episodeName].where((s) => s.isNotEmpty).join(' · ');

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Insets.lg, vertical: Insets.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: _kThumbWidth,
              child: Poster(url: item.imageUrl, radius: Radii.sm),
            ),
            const SizedBox(width: Insets.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  if (detail != null && detail.isNotEmpty) ...[
                    const SizedBox(height: Insets.xxs),
                    Text(
                      detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.bodySmall?.copyWith(color: context.scheme.onSurfaceVariant),
                    ),
                  ],
                  const SizedBox(height: Insets.xs),
                  _meta(context),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Time + kind, with a rewatch marker when this wasn't a first watch.
  Widget _meta(BuildContext context) {
    final t = AppLocalizations.of(context);
    final muted = context.text.labelSmall?.copyWith(color: context.scheme.onSurfaceVariant);
    return Row(
      children: [
        Icon(
          item.isMovie ? Icons.theaters_rounded : Icons.live_tv_rounded,
          size: 13,
          color: context.scheme.onSurfaceVariant,
        ),
        const SizedBox(width: Insets.xs),
        Flexible(
          child: Text(
            activityWhen(context, item.watchedAt),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: muted,
          ),
        ),
        if (item.isRewatch) ...[
          const SizedBox(width: Insets.sm),
          Icon(Icons.replay_rounded, size: 13, color: context.colors.seen),
          const SizedBox(width: Insets.xxs),
          Text(t.rewatched, style: muted?.copyWith(color: context.colors.seen)),
        ],
      ],
    );
  }
}
