import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../design/app_colors.dart';
import '../design/tokens.dart';
import '../l10n/app_localizations.dart';
import '../state/library_membership.dart';
import '../state/selection.dart';
import '../state/settings.dart';
import '../widgets/artwork_gallery.dart';
import '../widgets/badges.dart';
import '../widgets/net_image.dart';
import '../widgets/poster.dart';
import '../widgets/rating_thumbs.dart';
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
    final langs = context.read<SettingsController>().langsParam;
    _future = context.read<ApiClient>().movie(widget.movieId, langs: langs);
    context
        .read<ApiClient>()
        .movieRelation(widget.movieId)
        .then((r) {
          if (mounted) setState(() => _rel = r);
        })
        .catchError((_) {});
  }

  Future<void> _do(Future<MovieRelation> Function() action) async {
    final messenger = ScaffoldMessenger.of(context);
    final membership = context.read<LibraryMembership>();
    try {
      final r = await action();
      if (mounted) setState(() => _rel = r);
      // If the movie now has any tracking it's in the library; reflect it in the
      // overlay so its Discover card shows the marker without a reload.
      if (r.watched ||
          r.watchedCount > 0 ||
          r.isFavorited ||
          r.watchlist ||
          r.rating != null) {
        membership.add(SelKind.movie, widget.movieId);
      }
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
              icon: Icon(
                watched ? Icons.check_circle_rounded : Icons.add_rounded,
                size: 18,
              ),
              label: Text(
                watched
                    ? AppLocalizations.of(context).watchedTimes(count)
                    : AppLocalizations.of(context).markWatched,
              ),
              style: watched
                  ? FilledButton.styleFrom(backgroundColor: context.colors.seen)
                  : null,
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
            icon: Icon(
              later ? Icons.schedule_rounded : Icons.schedule_outlined,
              color: later ? context.scheme.tertiary : null,
            ),
            onPressed: () =>
                _do(() => api.watchlistMovie(widget.movieId, !later)),
          ),
          const SizedBox(width: Insets.sm),
          IconButton.outlined(
            tooltip: fav
                ? AppLocalizations.of(context).unfavorite
                : AppLocalizations.of(context).favorite,
            icon: Icon(
              fav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              color: fav ? context.colors.favorite : null,
            ),
            onPressed: () => _do(() => api.favoriteMovie(widget.movieId, !fav)),
          ),
        ],
      ),
    );
  }

  Future<void> _rate(int? rating) async {
    final api = context.read<ApiClient>();
    final membership = context.read<LibraryMembership>();
    final prev = _rel;
    // Optimistic: show the new rating right away, roll back if the call fails.
    if (prev != null) {
      setState(
        () => _rel = MovieRelation(
          movieId: prev.movieId,
          isFavorited: prev.isFavorited,
          watched: prev.watched,
          watchedCount: prev.watchedCount,
          watchlist: prev.watchlist,
          rating: rating,
        ),
      );
    }
    try {
      final r = await api.rateMovie(widget.movieId, rating);
      if (mounted) setState(() => _rel = r);
      if (rating != null) membership.add(SelKind.movie, widget.movieId);
    } catch (e) {
      if (!mounted) return;
      setState(() => _rel = prev);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Widget _ratingRow() => Padding(
    padding: const EdgeInsets.fromLTRB(Insets.lg, Insets.lg, Insets.lg, 0),
    child: RatingThumbs(value: _rel?.rating, onRate: _rate),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<Series>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const LoadingView();
          }
          if (snap.hasError) {
            return ErrorView(
              message: '${snap.error}',
              onRetry: () {
                final langs = context.read<SettingsController>().langsParam;
                final f = context.read<ApiClient>().movie(
                  widget.movieId,
                  langs: langs,
                );
                setState(() {
                  _future = f;
                });
              },
            );
          }
          final m = snap.data!;
          return Stack(
            children: [
              ListView(
                padding: EdgeInsets.zero,
                children: [
                  _hero(m),
                  _actionBar(),
                  _ratingRow(),
                  if (m.overview?.isNotEmpty ?? false)
                    Padding(
                      padding: const EdgeInsets.all(Insets.lg),
                      child: SelectableText(
                        m.overview!,
                        style: context.text.bodyMedium?.copyWith(height: 1.5),
                      ),
                    ),
                ],
              ),
              // Close affordance matches the show screen: a cross in the top-right
              // corner rather than a back arrow in the top-left.
              SafeArea(
                child: Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.all(Insets.sm),
                    child: CircleAvatar(
                      backgroundColor: context.colors.scrim.withValues(
                        alpha: 0.55,
                      ),
                      child: IconButton(
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Colors.white,
                        ),
                        onPressed: () => Navigator.pop(context),
                      ),
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

  void _openArtworks() => openArtworkGallery(
    context,
    context.read<ApiClient>().movieArtworks(widget.movieId),
  );

  Widget _hero(Series m) {
    final bg = Theme.of(context).scaffoldBackgroundColor;
    return SizedBox(
      height: 340,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Tap the backdrop (or the poster below) to browse the movie's artworks.
          GestureDetector(
            onTap: _openArtworks,
            child: NetImage(url: m.imageUrl),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  bg.withValues(alpha: 0.2),
                  bg.withValues(alpha: 0.55),
                  bg,
                ],
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
                SizedBox(
                  width: 120,
                  child: GestureDetector(
                    onTap: _openArtworks,
                    child: Poster(url: m.imageUrl),
                  ),
                ),
                const SizedBox(width: Insets.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SelectableText(
                        m.name ??
                            AppLocalizations.of(context).movieNumbered(m.id),
                        style: context.text.headlineSmall,
                        maxLines: 3,
                      ),
                      const SizedBox(height: Insets.sm),
                      Wrap(
                        spacing: Insets.sm,
                        children: [
                          Pill(label: AppLocalizations.of(context).movie),
                          if (m.year != null)
                            Pill(
                              label: '${m.year}',
                              color: context.scheme.onSurfaceVariant,
                            ),
                        ],
                      ),
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
