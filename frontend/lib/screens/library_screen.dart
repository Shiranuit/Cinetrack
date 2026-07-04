import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../api/filters.dart';
import '../api/models.dart';
import '../l10n/app_localizations.dart';
import '../design/app_colors.dart';
import '../design/tokens.dart';
import '../state/settings.dart';
import '../widgets/filter_sheet.dart';
import '../widgets/poster.dart';
import '../widgets/reveal.dart';
import '../widgets/infinite_grid.dart';
import '../widgets/poster_grid.dart';
import '../widgets/section.dart';
import '../widgets/show_actions.dart';
import '../widgets/show_card.dart';
import '../widgets/states.dart';
import 'movie_detail_screen.dart';
import 'show_detail_screen.dart';

enum _Filter { series, anime, movies }

/// The home tab: an inline search bar (results drop down from the bar and search
/// both series & movies), a Series/Movies/All filter, and the tracked rails.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  Timer? _debounce;
  bool _searchBusy = false;
  // Dropdown visibility is explicit (not tied to focus) so scrolling the results —
  // which dismisses the keyboard and drops focus — doesn't close them.
  bool _searchOpen = false;
  List<SearchResult>? _results;

  late Future<Library> _libFuture;
  // The type toggles are multi-select and combinable; all on = the whole library.
  Set<_Filter> _filter = {_Filter.series, _Filter.anime, _Filter.movies};

  // Advanced library filter (over the user's own shows). The token resets the
  // infinite grid to page 1 when the filter changes.
  final _f = AdvancedFilters();
  FilterOptions _filterOptions = const FilterOptions();
  int _filterToken = 0;

  late Future<List<LibraryMovie>> _moviesFuture;
  // Series + movies fetched together so the two can be shown in one combined
  // scroll when both type toggles are on.
  late Future<(Library, List<LibraryMovie>)> _content;

  @override
  void initState() {
    super.initState();
    _libFuture = context.read<ApiClient>().library(langs: _langs);
    _moviesFuture = context.read<ApiClient>().movies(langs: _langs);
    _content = _combine(_libFuture, _moviesFuture);
    _searchCtrl.addListener(_onSearchChanged);
    // Focusing the field (re)opens the dropdown; losing focus does NOT close it.
    _searchFocus.addListener(() {
      if (_searchFocus.hasFocus) setState(() => _searchOpen = true);
    });
    context.read<ApiClient>().filterOptions(library: true).then((o) {
      if (mounted) setState(() => _filterOptions = o);
    }).catchError((_) {});
  }

  bool get _filtering => _f.isActive;

  Future<void> _openFilters() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => FilterSheet(filters: _f, options: _filterOptions, showFavorites: true),
    );
    setState(() => _filterToken++);
  }

  Future<List<SearchResult>> _filterPage(int offset, int limit) => context
      .read<ApiClient>()
      .filteredSearch(_f, library: true, langs: _langs, offset: offset, limit: limit);

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  String get _langs => context.read<SettingsController>().langsParam;
  String get _query => _searchCtrl.text.trim();
  bool get _showDropdown => _searchOpen && _query.isNotEmpty;

  void _closeSearch() {
    setState(() => _searchOpen = false);
    _searchFocus.unfocus();
  }

  Future<(Library, List<LibraryMovie>)> _combine(
    Future<Library> lib,
    Future<List<LibraryMovie>> movies,
  ) async =>
      (await lib, await movies);

  Future<void> _reloadLibrary() async {
    final f = context.read<ApiClient>().library(langs: _langs);
    setState(() {
      _libFuture = f;
      _content = _combine(f, _moviesFuture);
    });
    await f;
  }

  /// Refresh both series and movies (used by the pull-to-refresh on the body).
  Future<void> _reloadContent() async {
    final lf = context.read<ApiClient>().library(langs: _langs);
    final mf = context.read<ApiClient>().movies(langs: _langs);
    setState(() {
      _libFuture = lf;
      _moviesFuture = mf;
      _content = _combine(lf, mf);
    });
    await _content;
  }

  void _onSearchChanged() {
    final q = _query;
    _debounce?.cancel();
    setState(() {
      if (q.isNotEmpty) _searchOpen = true;
    });
    // Require >= 3 characters before searching (matches the backend, which returns
    // nothing for shorter queries) — so typing on the way to a real term doesn't fire
    // a request per keystroke.
    if (q.trim().runes.length < 3) {
      setState(() {
        _results = null;
        _searchBusy = false;
      });
      return;
    }
    setState(() => _searchBusy = true);
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      try {
        // Search all types; keep series + movies.
        final r = await context.read<ApiClient>().search(q, langs: _langs);
        final filtered = r.where((e) => e.kind == 'series' || e.kind == 'movie').toList();
        if (mounted && _query == q) {
          setState(() {
            _results = filtered;
            _searchBusy = false;
          });
        }
      } catch (_) {
        if (mounted) setState(() => _searchBusy = false);
      }
    });
  }

  void _clearSearch() {
    _searchCtrl.clear();
    _closeSearch();
  }

  Future<void> _openResult(SearchResult r) async {
    if (r.tvdbId == null) return;
    _closeSearch();
    final route = r.kind == 'movie'
        ? MaterialPageRoute(builder: (_) => MovieDetailScreen(movieId: r.tvdbId!))
        : MaterialPageRoute(builder: (_) => ShowDetailScreen(seriesId: r.tvdbId!));
    await Navigator.of(context).push(route);
    await _reloadLibrary();
  }

  Future<void> _openShow(int seriesId) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ShowDetailScreen(seriesId: seriesId)));
    await _reloadLibrary();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Column(
          children: [
            _searchBar(),
            _filterBar(),
            Expanded(child: _filtering ? _filteredBody() : _libraryBody()),
          ],
        ),
        // Tap-outside barrier: closes the dropdown (keeps the query so tapping the
        // search bar again reopens it). Starts below the search bar so the field
        // stays tappable.
        if (_showDropdown)
          Positioned.fill(
            top: 60,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _closeSearch,
              child: const SizedBox.expand(),
            ),
          ),
        if (_showDropdown)
          Positioned(left: Insets.md, right: Insets.md, top: 62, child: _searchDropdown()),
      ],
    );
  }

  // Search field + view/filter controls share one row; the type selector gets its
  // own full-width row below so its labels never wrap.
  Widget _searchBar() {
    final t = AppLocalizations.of(context);
    final layout = context.watch<SettingsController>().libraryLayout;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Insets.lg, Insets.sm, Insets.lg, Insets.sm),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              focusNode: _searchFocus,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: t.searchHint,
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(icon: const Icon(Icons.close_rounded), onPressed: _clearSearch),
              ),
            ),
          ),
          IconButton(
            tooltip: layout == LibraryLayout.rails ? 'Grid view' : 'Carousel view',
            icon: Icon(layout == LibraryLayout.rails ? Icons.grid_view_rounded : Icons.view_carousel_rounded),
            onPressed: () => context.read<SettingsController>().toggleLibraryLayout(),
          ),
          Badge(
            isLabelVisible: _f.activeCount > 0,
            label: Text('${_f.activeCount}'),
            child: IconButton(
              tooltip: 'Filter library',
              icon: const Icon(Icons.tune_rounded),
              onPressed: _openFilters,
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterBar() {
    final t = AppLocalizations.of(context);
    Widget lbl(String s) => Text(s, maxLines: 1, softWrap: false, overflow: TextOverflow.fade);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Insets.lg, 0, Insets.lg, Insets.sm),
      child: SegmentedButton<_Filter>(
        multiSelectionEnabled: true,
        emptySelectionAllowed: true,
        showSelectedIcon: false,
        style: const ButtonStyle(visualDensity: VisualDensity.compact),
        segments: [
          ButtonSegment(value: _Filter.series, label: lbl(t.typeSeries), icon: const Icon(Icons.live_tv_rounded)),
          ButtonSegment(value: _Filter.anime, label: lbl(t.typeAnime), icon: const Icon(Icons.animation_rounded)),
          ButtonSegment(value: _Filter.movies, label: lbl(t.typeMovies), icon: const Icon(Icons.theaters_rounded)),
        ],
        selected: _filter,
        onSelectionChanged: (s) => setState(() => _filter = s),
      ),
    );
  }

  Widget _searchDropdown() {
    final maxH = MediaQuery.sizeOf(context).height * 0.6;
    return Material(
      elevation: 10,
      color: context.scheme.surfaceContainerHighest,
      borderRadius: Radii.card,
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: _searchBusy && _results == null
            ? const Padding(padding: EdgeInsets.all(Insets.xl), child: Center(child: CircularProgressIndicator()))
            : (_results?.isEmpty ?? true)
                ? Padding(padding: const EdgeInsets.all(Insets.lg), child: Text('No results', style: context.text.bodyMedium))
                : ListView.separated(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: _results!.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final r = _results![i];
                      final isMovie = r.kind == 'movie';
                      return ListTile(
                        leading: SizedBox(width: 38, height: 57, child: Poster(url: r.imageUrl, radius: Radii.sm)),
                        title: Text(r.name ?? '—', maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Row(
                          children: [
                            Icon(isMovie ? Icons.theaters_rounded : Icons.live_tv_rounded,
                                size: 13, color: context.scheme.onSurfaceVariant),
                            const SizedBox(width: 4),
                            Text([isMovie ? 'Movie' : 'Series', r.year?.toString()].where((e) => e != null).join(' · ')),
                          ],
                        ),
                        onTap: () => _openResult(r),
                      );
                    },
                  ),
      ),
    );
  }

  /// Flat, filtered view of the user's library (shown while filters are active),
  /// with lazy pagination.
  Widget _filteredBody() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Insets.lg, 0, Insets.lg, Insets.sm),
          child: Row(
            children: [
              Text(
                  _f.activeCount > 0
                      ? 'Filtered · ${_f.activeCount} active · ${kSorts[_f.sort] ?? ''}'
                      : 'Sorted by ${kSorts[_f.sort] ?? _f.sort}',
                  style: context.text.labelMedium?.copyWith(color: context.scheme.onSurfaceVariant)),
              const Spacer(),
              TextButton.icon(
                icon: const Icon(Icons.close_rounded, size: 16),
                label: Text(AppLocalizations.of(context).clear),
                onPressed: () => setState(() {
                  _f.reset();
                  _filterToken++;
                }),
              ),
            ],
          ),
        ),
        Expanded(
          child: InfiniteGrid(
            resetKey: _filterToken,
            fetchPage: _filterPage,
            empty: MessageView(
                icon: Icons.filter_alt_off_rounded, message: AppLocalizations.of(context).filterNoMatch),
            itemBuilder: (context, r) => ShowCard(
              title: r.name ?? 'Series ${r.tvdbId}',
              imageUrl: r.imageUrl,
              heroTag: 'series-${r.tvdbId}',
              onTap: r.tvdbId == null ? null : () => _openShow(r.tvdbId!),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _reloadMovies() async {
    final f = context.read<ApiClient>().movies(langs: _langs);
    setState(() {
      _moviesFuture = f;
      _content = _combine(_libFuture, f);
    });
    await f;
  }

  /// The library body: a single scroll combining the selected type sections —
  /// series categories (filtered by the Series/Anime toggles) and, if Movies is
  /// on, a Movies section. Respects the rails/grid layout preference.
  Widget _libraryBody() {
    final t = AppLocalizations.of(context);
    final wantSeries = _filter.contains(_Filter.series);
    final wantAnime = _filter.contains(_Filter.anime);
    final wantMovies = _filter.contains(_Filter.movies);

    if (_filter.isEmpty) {
      return _Scroll(
        child: MessageView(
          icon: Icons.filter_list_rounded,
          message: t.libSelectKinds,
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _reloadContent,
      child: FutureBuilder<(Library, List<LibraryMovie>)>(
        future: _content,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) return const _Scroll(child: LoadingView());
          if (snap.hasError) return _Scroll(child: ErrorView(message: '${snap.error}', onRetry: _reloadContent));
          final (lib, movies) = snap.data!;

          // Series categories, filtered to the selected kinds: a show is kept if
          // it's anime and Anime is on, or non-anime and Series is on.
          List<LibraryShow> pick(List<LibraryShow> l) =>
              l.where((s) => (wantAnime && s.isAnime) || (wantSeries && !s.isAnime)).toList();
          final cats = (wantSeries || wantAnime)
              ? <(_Cat, List<LibraryShow>)>[
                  (_cats[0], pick(lib.watching)),
                  (_cats[2], pick(lib.stale)), // Haven't watched in a while
                  (_cats[3], pick(lib.notStarted)), // Haven't started
                  (_cats[1], pick(lib.upToDate)), // Up to date
                  (_cats[4], pick(lib.stopped)),
                ].where((e) => e.$2.isNotEmpty).toList()
              : const <(_Cat, List<LibraryShow>)>[];
          final movieList = wantMovies ? movies : const <LibraryMovie>[];

          if (cats.isEmpty && movieList.isEmpty) {
            return _Scroll(
              child: MessageView(
                icon: Icons.video_library_rounded,
                message: t.libEmpty,
              ),
            );
          }

          final grid = context.watch<SettingsController>().libraryLayout == LibraryLayout.grid;
          var section = 0; // running index for staggered reveal
          return CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              for (final (cat, shows) in cats)
                ..._section(cat.title(t), cat.icon, cat.accent(context), shows.length, grid, section++,
                    (j) => _libraryCard(shows[j])),
              if (movieList.isNotEmpty)
                ..._section('Movies', Icons.theaters_rounded, context.scheme.tertiary, movieList.length, grid,
                    section++, (j) => _movieCard(movieList[j])),
              const SliverToBoxAdapter(child: SizedBox(height: Insets.xxl)),
            ],
          );
        },
      ),
    );
  }

  /// One library section as slivers: a horizontal rail, or a header + grid,
  /// depending on the layout preference.
  List<Widget> _section(
    String title,
    IconData icon,
    Color accent,
    int count,
    bool grid,
    int index,
    Widget Function(int) itemBuilder,
  ) {
    if (!grid) {
      return [
        SliverToBoxAdapter(
          child: Reveal(
            delay: Duration(milliseconds: index * 70),
            child: PosterRail(
              title: title,
              icon: icon,
              accent: accent,
              count: count,
              itemBuilder: (context, j) => itemBuilder(j),
            ),
          ),
        ),
      ];
    }
    return [
      SliverToBoxAdapter(
        child: SectionHeader(
          title: title,
          icon: icon,
          accent: accent,
          trailing: Text('$count', style: context.text.labelMedium?.copyWith(color: context.scheme.onSurfaceVariant)),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(Insets.lg, 0, Insets.lg, Insets.lg),
        sliver: SliverGrid(
          gridDelegate: posterGridDelegate(context),
          delegate: SliverChildBuilderDelegate((context, j) => itemBuilder(j), childCount: count),
        ),
      ),
    ];
  }

  ShowCard _libraryCard(LibraryShow s) => ShowCard(
        title: s.name ?? 'Series ${s.seriesId}',
        imageUrl: s.imageUrl,
        favorite: s.isFavorited,
        progress: s.progress,
        // Progress bar replaces the "N watched" caption.
        heroTag: 'series-${s.seriesId}',
        onTap: () => _openShow(s.seriesId),
        onLongPress: () => showShowContextSheet(
          context,
          seriesId: s.seriesId,
          title: s.name ?? 'Series ${s.seriesId}',
          onChanged: _reloadLibrary,
        ),
      );

  ShowCard _movieCard(LibraryMovie m) => ShowCard(
        title: m.name ?? 'Movie ${m.movieId}',
        imageUrl: m.imageUrl,
        subtitle: m.year?.toString(),
        favorite: m.isFavorited,
        onTap: () async {
          await Navigator.of(context).push(MaterialPageRoute(builder: (_) => MovieDetailScreen(movieId: m.movieId)));
          await _reloadMovies();
        },
      );
}

typedef _AccentFn = Color Function(BuildContext);

class _Cat {
  const _Cat(this.title, this.icon, this.accent);
  final String Function(AppLocalizations) title;
  final IconData icon;
  final _AccentFn accent;
}

final _cats = <_Cat>[
  _Cat((t) => t.catWatching, Icons.play_circle_rounded, (c) => c.scheme.primary),
  _Cat((t) => t.catUpToDate, Icons.check_circle_rounded, (c) => c.colors.seen),
  _Cat((t) => t.catStale, Icons.history_rounded, (c) => c.colors.warning),
  _Cat((t) => t.catNotStarted, Icons.playlist_add_rounded, (c) => c.scheme.secondary),
  _Cat((t) => t.catStopped, Icons.pause_circle_rounded, (c) => c.scheme.onSurfaceVariant),
];

class _Scroll extends StatelessWidget {
  const _Scroll({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [SizedBox(height: MediaQuery.sizeOf(context).height * 0.28), child],
      );
}
