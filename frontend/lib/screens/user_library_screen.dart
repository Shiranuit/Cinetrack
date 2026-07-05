import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../api/filters.dart';
import '../api/models.dart';
import '../design/app_colors.dart';
import '../design/tokens.dart';
import '../l10n/app_localizations.dart';
import '../state/settings.dart';
import '../widgets/filter_sheet.dart';
import '../widgets/poster_grid.dart';
import '../widgets/section.dart';
import '../widgets/show_card.dart';
import '../widgets/states.dart';
import 'movie_detail_screen.dart';
import 'show_detail_screen.dart';

enum _Tab { series, movies, all }

/// A friend's library — categorized rails (Watching / Up to date / …) with
/// progress, plus a Series/Movies/All selector and advanced Filter/Sort to
/// search inside their shows. Read-only; privacy-gated on the backend.
class UserLibraryScreen extends StatefulWidget {
  const UserLibraryScreen({super.key, required this.userId, required this.title});
  final String userId;
  final String title;
  @override
  State<UserLibraryScreen> createState() => _UserLibraryScreenState();
}

class _UserLibraryScreenState extends State<UserLibraryScreen> {
  final _f = AdvancedFilters()..type = 'series';
  FilterOptions _options = const FilterOptions();
  _Tab _tab = _Tab.series;

  late Future<Library> _libFuture;
  late Future<List<LibraryMovie>> _moviesFuture;
  Future<List<SearchResult>>? _filteredFuture;

  String get _langs => context.read<SettingsController>().langsParam;
  bool get _filtering => _f.isActive;

  @override
  void initState() {
    super.initState();
    final api = context.read<ApiClient>();
    _libFuture = api.userLibrary(widget.userId, langs: _langs);
    _moviesFuture = api.userMovies(widget.userId, langs: _langs);
    api.filterOptions().then((o) {
      if (mounted) setState(() => _options = o);
    }).catchError((_) {});
  }

  Future<void> _openFilters() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => FilterSheet(filters: _f, options: _options, showFavorites: true),
    );
    setState(() {
      _filteredFuture = _filtering
          ? context.read<ApiClient>().userFilteredShows(widget.userId, _f, langs: _langs)
          : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Insets.lg, Insets.sm, Insets.lg, Insets.sm),
            child: Row(
              children: [
                Expanded(
                  child: SegmentedButton<_Tab>(
                    showSelectedIcon: false,
                    style: const ButtonStyle(visualDensity: VisualDensity.compact),
                    segments: [
                      ButtonSegment(
                          value: _Tab.series,
                          label: Text(t.typeSeries, maxLines: 1, softWrap: false, overflow: TextOverflow.fade)),
                      ButtonSegment(
                          value: _Tab.movies,
                          label: Text(t.typeMovies, maxLines: 1, softWrap: false, overflow: TextOverflow.fade)),
                      ButtonSegment(
                          value: _Tab.all,
                          label: Text(t.typeAll, maxLines: 1, softWrap: false, overflow: TextOverflow.fade)),
                    ],
                    selected: {_tab},
                    onSelectionChanged: (s) => setState(() => _tab = s.first),
                  ),
                ),
                const SizedBox(width: Insets.sm),
                Badge(
                  isLabelVisible: _f.activeCount > 0,
                  label: Text('${_f.activeCount}'),
                  child: IconButton(
                    tooltip: t.filterAndSort,
                    icon: const Icon(Icons.tune_rounded),
                    onPressed: _openFilters,
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    if (_tab == _Tab.movies) return _moviesGrid();
    if (_filtering) return _filteredGrid();
    return _categorized();
  }

  Widget _categorized() {
    return FutureBuilder<Library>(
      future: _libFuture,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) return const LoadingView();
        if (snap.hasError) return ErrorView(message: '${snap.error}', onRetry: () {});
        final lib = snap.data!;
        final t = AppLocalizations.of(context);
        final cats = <(String, IconData, Color, List<LibraryShow>)>[
          (t.catWatching, Icons.play_circle_rounded, context.scheme.primary, lib.watching),
          (t.catStale, Icons.history_rounded, context.colors.warning, lib.stale),
          (t.catNotStarted, Icons.playlist_add_rounded, context.scheme.secondary, lib.notStarted),
          (t.catUpToDate, Icons.check_circle_rounded, context.colors.seen, lib.upToDate),
          (t.catStopped, Icons.pause_circle_rounded, context.scheme.onSurfaceVariant, lib.stopped),
        ].where((e) => e.$4.isNotEmpty).toList();
        if (cats.isEmpty) return MessageView(icon: Icons.video_library_rounded, message: t.libNoShows);
        return ListView(
          padding: const EdgeInsets.only(bottom: Insets.xxl),
          children: [
            for (final (title, icon, accent, shows) in cats)
              PosterRail(
                title: title,
                icon: icon,
                accent: accent,
                count: shows.length,
                itemBuilder: (context, i) {
                  final s = shows[i];
                  return ShowCard(
                    title: s.name ?? t.seriesFallback(s.seriesId),
                    imageUrl: s.imageUrl,
                    favorite: s.isFavorited,
                    progress: s.progress,
                    onTap: () => _openShow(s.seriesId),
                  );
                },
              ),
          ],
        );
      },
    );
  }

  Widget _filteredGrid() {
    return FutureBuilder<List<SearchResult>>(
      future: _filteredFuture,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) return const LoadingView();
        if (snap.hasError) return ErrorView(message: '${snap.error}', onRetry: _openFilters);
        final items = snap.data ?? [];
        if (items.isEmpty) {
          return MessageView(
              icon: Icons.filter_alt_off_rounded, message: AppLocalizations.of(context).filterNoMatch);
        }
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(Insets.lg, Insets.sm, Insets.lg, Insets.xxl),
          gridDelegate: posterGridDelegate(context),
          itemCount: items.length,
          itemBuilder: (context, i) {
            final r = items[i];
            return ShowCard(
              title: r.name ?? '—',
              imageUrl: r.imageUrl,
              subtitle: r.year?.toString(),
              onTap: r.tvdbId == null ? null : () => _openShow(r.tvdbId!),
            );
          },
        );
      },
    );
  }

  Widget _moviesGrid() {
    return FutureBuilder<List<LibraryMovie>>(
      future: _moviesFuture,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) return const LoadingView();
        if (snap.hasError) return ErrorView(message: '${snap.error}', onRetry: () {});
        final movies = snap.data ?? [];
        final t = AppLocalizations.of(context);
        if (movies.isEmpty) {
          return MessageView(
              icon: Icons.theaters_rounded, message: t.noTrackedMovies);
        }
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(Insets.lg, Insets.sm, Insets.lg, Insets.xxl),
          gridDelegate: posterGridDelegate(context),
          itemCount: movies.length,
          itemBuilder: (context, i) {
            final m = movies[i];
            return ShowCard(
              title: m.name ?? t.movieFallback(m.movieId),
              imageUrl: m.imageUrl,
              subtitle: m.year?.toString(),
              favorite: m.isFavorited,
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => MovieDetailScreen(movieId: m.movieId))),
            );
          },
        );
      },
    );
  }

  void _openShow(int seriesId) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => ShowDetailScreen(seriesId: seriesId)));
}

/// A flat grid of shows (used for "Favorites → See all").
class ShowsGridScreen extends StatelessWidget {
  const ShowsGridScreen({super.key, required this.title, required this.shows});
  final String title;
  final List<UserShow> shows;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: shows.isEmpty
          ? MessageView(icon: Icons.favorite_border_rounded, message: t.nothingHereYet)
          : GridView.builder(
              padding: const EdgeInsets.fromLTRB(Insets.lg, Insets.sm, Insets.lg, Insets.xxl),
              gridDelegate: posterGridDelegate(context),
              itemCount: shows.length,
              itemBuilder: (context, i) {
                final s = shows[i];
                return ShowCard(
                  title: s.name ?? t.seriesFallback(s.seriesId),
                  imageUrl: s.imageUrl,
                  favorite: s.isFavorited,
                  subtitle: s.rating != null ? t.ratingStars(s.rating!) : null,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => ShowDetailScreen(seriesId: s.seriesId)),
                  ),
                );
              },
            ),
    );
  }
}
