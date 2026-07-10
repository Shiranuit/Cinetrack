import 'dart:async';

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
import '../widgets/rating_thumbs.dart';
import '../widgets/section.dart';
import '../widgets/show_card.dart';
import '../widgets/states.dart';
import 'movie_detail_screen.dart';
import 'show_detail_screen.dart';

enum _Kind { series, anime, movies }

/// A friend's library — mirrors your own Library: a search bar that searches
/// inside THEIR shows (composed with the advanced Filter/Sort), a multi-select
/// Series/Anime/Movies toggle, and the tracked rails with their ratings/favorites.
/// Read-only; privacy-gated on the backend.
class UserLibraryScreen extends StatefulWidget {
  const UserLibraryScreen({super.key, required this.userId, required this.title, this.startOnMovies = false});
  final String userId;
  final String title;

  /// Open showing only Movies (e.g. from a profile's "Movies → See all").
  final bool startOnMovies;
  @override
  State<UserLibraryScreen> createState() => _UserLibraryScreenState();
}

class _UserLibraryScreenState extends State<UserLibraryScreen> {
  // Default to the OWNER's rating so their library reads as their ranking (the
  // backend resolves "my_rating" to the browsed user when viewing their library).
  final _f = AdvancedFilters(defaultSort: 'my_rating')..type = 'series';
  FilterOptions _options = const FilterOptions();
  // Type toggles, multi-select and combinable (all on by default).
  late Set<_Kind> _kinds = widget.startOnMovies ? {_Kind.movies} : {_Kind.series, _Kind.anime, _Kind.movies};

  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  int _filterToken = 0; // bumped to re-key the filtered grid

  late Future<Library> _libFuture;
  late Future<List<LibraryMovie>> _moviesFuture;
  // Non-null only while a search/filter is active (the flat filtered view).
  Future<List<SearchResult>>? _filteredFuture;

  String get _langs => context.read<SettingsController>().langsParam;
  bool get _filtering => _f.isActive;

  @override
  void initState() {
    super.initState();
    final api = context.read<ApiClient>();
    _libFuture = api.userLibrary(widget.userId, langs: _langs);
    _moviesFuture = api.userMovies(widget.userId, langs: _langs);
    _searchCtrl.addListener(_onSearchChanged);
    api.filterOptions().then((o) {
      if (mounted) setState(() => _options = o);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Backend kinds for the current toggles. "series" already includes anime, so
  /// "anime" is only queried separately when "series" is off.
  List<String> _backendKinds() {
    final k = <String>[];
    if (_kinds.contains(_Kind.series)) {
      k.add('series');
    } else if (_kinds.contains(_Kind.anime)) {
      k.add('anime');
    }
    if (_kinds.contains(_Kind.movies)) k.add('movie');
    return k;
  }

  void _recomputeFiltered() {
    _filteredFuture = _filtering ? _fetchFiltered() : null;
  }

  /// Fan out the current search/filter over the selected kinds (series and/or
  /// movies) inside THIS user's library, and merge.
  Future<List<SearchResult>> _fetchFiltered() async {
    final kinds = _backendKinds();
    if (kinds.isEmpty) return [];
    final api = context.read<ApiClient>();
    final lists =
        await Future.wait(kinds.map((k) => api.userFilteredShows(widget.userId, _f, type: k, langs: _langs)));
    return [for (final l in lists) ...l];
  }

  // Search inside their library by name; writes the query into `_f` (so it
  // composes with the filter) and re-runs the flat filtered view.
  void _onSearchChanged() {
    final q = _searchCtrl.text.trim();
    setState(() {}); // refresh the clear button
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted || q == _f.query) return;
      setState(() {
        _f.query = q;
        _filterToken++;
        _recomputeFiltered();
      });
    });
  }

  void _clearSearch() {
    _searchCtrl.clear();
    _debounce?.cancel();
    setState(() {
      _f.query = '';
      _filterToken++;
      _recomputeFiltered();
    });
  }

  Future<void> _openFilters() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => FilterSheet(filters: _f, options: _options, showFavorites: true, othersLibrary: true),
    );
    setState(() {
      _filterToken++;
      _recomputeFiltered();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(
        children: [
          _searchBar(),
          _filterBar(),
          Expanded(child: _filtering ? _filteredGrid() : _categorized()),
        ],
      ),
    );
  }

  // Row 1: search bar + Filter/Sort icon (same layout as your own Library).
  Widget _searchBar() {
    final t = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Insets.lg, Insets.sm, Insets.lg, 0),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: t.searchThisLibrary,
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchCtrl.text.isEmpty
                    ? null
                    : IconButton(icon: const Icon(Icons.close_rounded), onPressed: _clearSearch),
              ),
            ),
          ),
          const SizedBox(width: Insets.sm),
          Badge(
            isLabelVisible: _f.activeCount > 0,
            label: Text('${_f.activeCount}'),
            child: IconButton.filledTonal(
              tooltip: t.filterAndSort,
              icon: const Icon(Icons.tune_rounded),
              onPressed: _openFilters,
            ),
          ),
        ],
      ),
    );
  }

  // Row 2: multi-select Series/Anime/Movies toggle.
  Widget _filterBar() {
    final t = AppLocalizations.of(context);
    Widget lbl(String s) => Text(s, maxLines: 1, softWrap: false, overflow: TextOverflow.fade);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Insets.lg, Insets.sm, Insets.lg, Insets.sm),
      child: SegmentedButton<_Kind>(
        multiSelectionEnabled: true,
        emptySelectionAllowed: true,
        showSelectedIcon: false,
        style: const ButtonStyle(visualDensity: VisualDensity.compact),
        segments: [
          ButtonSegment(value: _Kind.series, label: lbl(t.typeSeries)),
          ButtonSegment(value: _Kind.anime, label: lbl(t.typeAnime)),
          ButtonSegment(value: _Kind.movies, label: lbl(t.typeMovies)),
        ],
        selected: _kinds,
        onSelectionChanged: (s) => setState(() {
          _kinds = s;
          _filterToken++;
          _recomputeFiltered();
        }),
      ),
    );
  }

  /// The categorized view: series category rails (filtered to the selected kinds)
  /// plus a Movies rail, in one scroll — mirrors your own Library.
  Widget _categorized() {
    final t = AppLocalizations.of(context);
    final wantSeries = _kinds.contains(_Kind.series);
    final wantAnime = _kinds.contains(_Kind.anime);
    final wantMovies = _kinds.contains(_Kind.movies);
    if (_kinds.isEmpty) {
      return MessageView(icon: Icons.filter_list_rounded, message: t.libSelectKinds);
    }
    return FutureBuilder<List<dynamic>>(
      future: Future.wait([_libFuture, _moviesFuture]),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) return const LoadingView();
        if (snap.hasError) return ErrorView(message: '${snap.error}', onRetry: () => setState(() {}));
        final lib = snap.data![0] as Library;
        final movies = snap.data![1] as List<LibraryMovie>;
        // Keep a show if it's anime and Anime is on, or non-anime and Series is on.
        List<LibraryShow> pick(List<LibraryShow> l) =>
            l.where((s) => (wantAnime && s.isAnime) || (wantSeries && !s.isAnime)).toList();
        final children = <Widget>[
          ..._seriesRails(lib, t, pick),
          if (wantMovies && movies.isNotEmpty) _moviesRailFor(movies, t),
        ];
        if (children.isEmpty) return MessageView(icon: Icons.video_library_rounded, message: t.libNoShows);
        return ListView(padding: const EdgeInsets.only(bottom: Insets.xxl), children: children);
      },
    );
  }

  /// The series categories as horizontal rails (Watching / Up to date / …),
  /// filtered to the selected kinds via [pick].
  List<Widget> _seriesRails(Library lib, AppLocalizations t, List<LibraryShow> Function(List<LibraryShow>) pick) {
    final cats = <(String, IconData, Color, List<LibraryShow>)>[
      (t.catWatching, Icons.play_circle_rounded, context.scheme.primary, pick(lib.watching)),
      (t.catStale, Icons.history_rounded, context.colors.warning, pick(lib.stale)),
      (t.catNotStarted, Icons.playlist_add_rounded, context.scheme.secondary, pick(lib.notStarted)),
      (t.watchLater, Icons.schedule_rounded, context.scheme.tertiary, pick(lib.forLater)),
      (t.catUpToDate, Icons.check_circle_rounded, context.colors.seen, pick(lib.upToDate)),
      (t.catStopped, Icons.pause_circle_rounded, context.scheme.onSurfaceVariant, pick(lib.stopped)),
    ].where((e) => e.$4.isNotEmpty).toList();
    return [
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
              rating: s.rating,
              progress: s.progress,
              onTap: () => _openShow(s.seriesId),
            );
          },
        ),
    ];
  }

  /// A single rail of tracked movies (shown inside the categorized view).
  Widget _moviesRailFor(List<LibraryMovie> movies, AppLocalizations t) => PosterRail(
        title: t.typeMovies,
        icon: Icons.theaters_rounded,
        accent: context.scheme.tertiary,
        count: movies.length,
        itemBuilder: (context, i) {
          final m = movies[i];
          return ShowCard(
            title: m.name ?? t.movieFallback(m.movieId),
            imageUrl: m.imageUrl,
            subtitle: m.year?.toString(),
            favorite: m.isFavorited,
            rating: m.rating,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => MovieDetailScreen(movieId: m.movieId))),
          );
        },
      );

  /// The flat filtered/searched view (shown while a search or filter is active).
  Widget _filteredGrid() {
    return FutureBuilder<List<SearchResult>>(
      future: _filteredFuture,
      key: ValueKey(_filterToken),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) return const LoadingView();
        if (snap.hasError) return ErrorView(message: '${snap.error}', onRetry: () => setState(_recomputeFiltered));
        final items = snap.data ?? [];
        if (items.isEmpty) {
          return MessageView(icon: Icons.search_off_rounded, message: AppLocalizations.of(context).filterNoMatch);
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
              rating: r.rating,
              favorite: r.isFavorited,
              onTap: r.tvdbId == null
                  ? null
                  : () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => r.kind == 'movie'
                          ? MovieDetailScreen(movieId: r.tvdbId!)
                          : ShowDetailScreen(seriesId: r.tvdbId!))),
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
                  subtitle: s.rating != null ? ratingLevelLabel(context, s.rating!) : null,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => ShowDetailScreen(seriesId: s.seriesId)),
                  ),
                );
              },
            ),
    );
  }
}
