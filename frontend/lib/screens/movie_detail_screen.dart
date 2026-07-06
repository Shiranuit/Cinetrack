import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../design/app_colors.dart';
import '../design/tokens.dart';
import '../l10n/app_localizations.dart';
import '../state/settings.dart';
import '../widgets/badges.dart';
import '../widgets/net_image.dart';
import '../widgets/poster.dart';
import '../widgets/states.dart';

/// Movie view with tracking (mark watched / rewatch / favorite).
class MovieDetailScreen extends StatefulWidget {
  const MovieDetailScreen({super.key, required this.movieId});
  final int movieId;
  @override
  State<MovieDetailScreen> createState() => _MovieDetailScreenState();
}

class _MovieDetailScreenState extends State<MovieDetailScreen> {
  late Future<Series> _future;
  MovieRelation? _rel;

  @override
  void initState() {
    super.initState();
    final lang = context.read<SettingsController>().languages.first;
    _future = context.read<ApiClient>().movie(widget.movieId, lang: lang);
    context.read<ApiClient>().movieRelation(widget.movieId).then((r) {
      if (mounted) setState(() => _rel = r);
    }).catchError((_) {});
  }

  Future<void> _do(Future<MovieRelation> Function() action) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final r = await action();
      if (mounted) setState(() => _rel = r);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Widget _actionBar() {
    final api = context.read<ApiClient>();
    final rel = _rel;
    final watched = rel?.watched ?? false;
    final count = rel?.watchedCount ?? 0;
    final fav = rel?.isFavorited ?? false;
    final later = rel?.watchlist ?? false;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Insets.lg, Insets.lg, Insets.lg, 0),
      child: Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              icon: Icon(watched ? Icons.check_circle_rounded : Icons.add_rounded, size: 18),
              label: Text(watched ? AppLocalizations.of(context).watchedTimes(count) : AppLocalizations.of(context).markWatched),
              style: watched ? FilledButton.styleFrom(backgroundColor: context.colors.seen) : null,
              onPressed: () => _do(() => api.watchMovie(widget.movieId)),
            ),
          ),
          if (watched) ...[
            const SizedBox(width: Insets.sm),
            IconButton.outlined(
              tooltip: AppLocalizations.of(context).removeOneWatch,
              icon: const Icon(Icons.remove_rounded),
              onPressed: () => _do(() => api.unwatchMovie(widget.movieId)),
            ),
          ],
          const SizedBox(width: Insets.sm),
          IconButton.outlined(
            tooltip: AppLocalizations.of(context).watchLater,
            icon: Icon(later ? Icons.schedule_rounded : Icons.schedule_outlined,
                color: later ? context.scheme.tertiary : null),
            onPressed: () => _do(() => api.watchlistMovie(widget.movieId, !later)),
          ),
          const SizedBox(width: Insets.sm),
          IconButton.outlined(
            tooltip: fav ? AppLocalizations.of(context).unfavorite : AppLocalizations.of(context).favorite,
            icon: Icon(fav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                color: fav ? context.colors.favorite : null),
            onPressed: () => _do(() => api.favoriteMovie(widget.movieId, !fav)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<Series>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) return const LoadingView();
          if (snap.hasError) {
            return ErrorView(message: '${snap.error}', onRetry: () {
              final lang = context.read<SettingsController>().languages.first;
              final f = context.read<ApiClient>().movie(widget.movieId, lang: lang);
              setState(() {
                _future = f;
              });
            });
          }
          final m = snap.data!;
          return Stack(
            children: [
              ListView(
                padding: EdgeInsets.zero,
                children: [
                  _hero(m),
                  _actionBar(),
                  if (m.overview?.isNotEmpty ?? false)
                    Padding(
                      padding: const EdgeInsets.all(Insets.lg),
                      child: Text(m.overview!, style: context.text.bodyMedium?.copyWith(height: 1.5)),
                    ),
                ],
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(Insets.sm),
                  child: CircleAvatar(
                    backgroundColor: context.colors.scrim.withValues(alpha: 0.55),
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _hero(Series m) {
    final bg = Theme.of(context).scaffoldBackgroundColor;
    return SizedBox(
      height: 340,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
            child: NetImage(url: m.imageUrl),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [bg.withValues(alpha: 0.2), bg.withValues(alpha: 0.55), bg],
                stops: const [0, 0.55, 1],
              ),
            ),
          ),
          Positioned(
            left: Insets.lg,
            right: Insets.lg,
            bottom: Insets.lg,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                SizedBox(width: 120, child: Poster(url: m.imageUrl)),
                const SizedBox(width: Insets.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(m.name ?? AppLocalizations.of(context).movieNumbered(m.id),
                          style: context.text.headlineSmall, maxLines: 3, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: Insets.sm),
                      Wrap(spacing: Insets.sm, children: [
                        Pill(label: AppLocalizations.of(context).movie),
                        if (m.year != null) Pill(label: '${m.year}', color: context.scheme.onSurfaceVariant),
                      ]),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
