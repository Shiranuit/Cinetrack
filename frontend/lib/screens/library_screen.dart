import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../api/filters.dart';
import '../api/models.dart';
import '../l10n/app_localizations.dart';
import '../design/app_colors.dart';
import '../design/tokens.dart';
import '../state/selection.dart';
import '../state/settings.dart';
import '../widgets/bulk_action_bar.dart';
import '../widgets/filter_sheet.dart';
import '../widgets/reveal.dart';
import '../widgets/infinite_grid.dart';
import '../widgets/poster_grid.dart';
import '../widgets/library_categories.dart';
import '../widgets/library_customize_sheet.dart';
import '../widgets/section.dart';
import '../widgets/show_card.dart';
import '../widgets/states.dart';
import 'movie_detail_screen.dart';
import 'show_detail_screen.dart';

enum _Filter { series, anime, movies }

/// The home tab: a search bar that searches YOUR library by name (composed with
/// the advanced filter), a Series/Anime/Movies toggle, and the tracked rails.
/// Full-catalog search lives in Discover.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  // The search bar searches YOUR library (by name), composed with the filter —
  // both live in `_f`, so search + filter operate on the same (library) scope.
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  late Future<Library> _libFuture;
  // The type toggles are multi-select and combinable; all on = the whole library.
  Set<_Filter> _filter = {_Filter.series, _Filter.anime, _Filter.movies};

  // Advanced library filter (over the user's own shows). The token resets the
  // infinite grid to page 1 when the filter changes.
  final _f = AdvancedFilters(defaultSort: 'my_rating');
  FilterOptions _filterOptions = const FilterOptions();
  int _filterToken = 0;

  // The user's layout: which sections show, in what order. Server-owned so it
  // follows them across devices; the built-in defaults render until it arrives.
  List<LibrarySection> _sections = defaultLibrarySections();

  // Items for each enabled CUSTOM section, keyed by section id. Filled in as the
  // per-section requests resolve, so one slow saved filter doesn't hold up the
  // whole library — a section simply appears once its rail has content.
  final Map<String, List<SearchResult>> _customItems = {};

  late Future<List<LibraryMovie>> _moviesFuture;
  // Series + movies fetched together so the two can be shown in one combined
  // scroll when both type toggles are on.
  late Future<(Library, List<LibraryMovie>)> _content;
  // Last successfully loaded content, kept so a background auto-refresh doesn't
  // flash the whole library to a spinner while it reloads.
  (Library, List<LibraryMovie>)? _lastContent;

  // The API client is a change signal too: any authenticated write notifies it,
  // so an add / watch / favorite from anywhere refreshes the library on its own.
  late final ApiClient _api;
  Timer? _refreshDebounce;
  final _selection = SelectionController();
  final _bodyScroll = ScrollController(); // kept across reloads so scroll survives

  @override
  void initState() {
    super.initState();
    _api = context.read<ApiClient>();
    _libFuture = _api.library(langs: _langs, sort: _f.sort, dir: _f.sortDesc ? 'desc' : 'asc');
    _moviesFuture = _api.movies(langs: _langs, sort: _f.sort, dir: _f.sortDesc ? 'desc' : 'asc');
    _content = _combine(_libFuture, _moviesFuture);
    _searchCtrl.addListener(_onSearchChanged);
    _api.addListener(_onExternalMutation);
    _api.filterOptions(library: true).then((o) {
      if (mounted) setState(() => _filterOptions = o);
    }).catchError((_) {});
    _loadSections();
  }

  /// Fetch the saved layout, then the contents of its custom sections. Failure is
  /// silent by design: the built-in defaults are already on screen, so a layout
  /// that won't load costs the user their customization, not their library.
  Future<void> _loadSections() async {
    try {
      final sections = await _api.librarySections();
      if (!mounted) return;
      setState(() => _sections = sections);
      await _loadCustomSections();
    } catch (_) {
      /* keep the defaults */
    }
  }

  /// Whether one kind is currently shown by the type toggles.
  bool _kindSelected(String kind) => switch (kind) {
        'movie' => _filter.contains(_Filter.movies),
        'anime' => _filter.contains(_Filter.anime),
        _ => _filter.contains(_Filter.series),
      };

  /// Whether any of a section's kinds is on. A section spanning Series + Movies
  /// stays visible while either is selected; its contents are narrowed to the
  /// selected kinds by [_loadCustomSections].
  bool _customTypeVisible(LibrarySection s) => s.kinds.any(_kindSelected);

  /// Load every custom rail in ONE request.
  ///
  /// A section can span several kinds and the filter endpoint takes one at a time,
  /// so this flattens to one batch entry per (section, kind) — keyed so the
  /// responses can be regrouped — and merges each section's kinds back together.
  /// The kinds are intersected with the screen's type toggles first, so toggling
  /// Movies off empties the movie half of a mixed section rather than leaving it
  /// stale.
  Future<void> _loadCustomSections() async {
    final custom = _sections.where((s) => s.enabled && s.isCustom && s.id != null).toList();
    if (custom.isEmpty) return;

    // Resolved once and reused below, so the request and the regrouping can't
    // disagree about which kinds a section covers.
    final plan = {
      for (final s in custom)
        s.id!: (filters: mergedSectionFilters(s, _f), kinds: s.kinds.where(_kindSelected).toSet()),
    };
    final entries = [
      for (final s in custom)
        for (final kind in sectionQueryKinds(plan[s.id!]!.kinds))
          (
            key: sectionBatchKey(s.id!, kind),
            filters: sectionQueryFilters(plan[s.id!]!.filters, kind, plan[s.id!]!.kinds),
          ),
    ];

    try {
      final byKey = entries.isEmpty
          ? const <String, List<SearchResult>>{}
          : await _api.librarySectionsItems(entries, langs: _langs);
      if (!mounted) return;
      setState(() {
        for (final s in custom) {
          final p = plan[s.id!]!;
          _customItems[s.id!] = mergeSectionResults(
            [
              for (final kind in sectionQueryKinds(p.kinds))
                byKey[sectionBatchKey(s.id!, kind)] ?? const <SearchResult>[],
            ],
            p.kinds,
            sort: p.filters['sort'],
            desc: (p.filters['dir'] ?? 'desc') != 'asc',
          );
        }
      });
    } catch (_) {
      // One request now, so a failure takes every rail with it — show them empty
      // rather than leaving stale contents from a previous filter.
      if (mounted) {
        setState(() {
          for (final s in custom) {
            _customItems[s.id!] = const [];
          }
        });
      }
    }
  }

  /// A write happened somewhere (any authenticated ApiClient call) — quietly
  /// reload series + movies. Debounced so a burst (e.g. marking a whole season)
  /// collapses into a single reload.
  void _onExternalMutation() {
    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) _reloadContent();
    });
  }

  bool get _filtering => _f.isActive;

  Future<void> _openFilters() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => FilterSheet(filters: _f, options: _filterOptions, showFavorites: true),
    );
    setState(() => _filterToken++); // reset the flat/filtered grid
    // The sort may have changed; the categorized view is ordered server-side, so
    // reload it with the new sort.
    _reloadContent();
  }

  /// Backend kinds for the current type toggles. "series" already includes anime,
  /// so "anime" is only queried separately when "series" is off.
  List<String> _backendKinds() {
    final k = <String>[];
    if (_filter.contains(_Filter.series)) {
      k.add('series');
    } else if (_filter.contains(_Filter.anime)) {
      k.add('anime');
    }
    if (_filter.contains(_Filter.movies)) k.add('movie');
    return k;
  }

  /// One page of the filtered/searched library: fan out over the selected type
  /// toggles and merge, so a search spans your series AND movies.
  Future<List<SearchResult>> _filterPage(int offset, int limit) async {
    final kinds = _backendKinds();
    if (kinds.isEmpty) return [];
    final api = context.read<ApiClient>();
    final lists = await Future.wait(kinds
        .map((k) => api.filteredSearch(_f, library: true, type: k, langs: _langs, offset: offset, limit: limit)));
    return [for (final l in lists) ...l];
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _refreshDebounce?.cancel();
    _api.removeListener(_onExternalMutation);
    _searchCtrl.dispose();
    _selection.dispose();
    _bodyScroll.dispose();
    super.dispose();
  }

  String get _langs => context.read<SettingsController>().langsParam;

  Future<(Library, List<LibraryMovie>)> _combine(
    Future<Library> lib,
    Future<List<LibraryMovie>> movies,
  ) async =>
      (await lib, await movies);

  /// Refresh both series and movies (used by the pull-to-refresh on the body).
  Future<void> _reloadContent() async {
    final lf = context.read<ApiClient>().library(langs: _langs, sort: _f.sort, dir: _f.sortDesc ? 'desc' : 'asc');
    final mf = context.read<ApiClient>().movies(langs: _langs, sort: _f.sort, dir: _f.sortDesc ? 'desc' : 'asc');
    setState(() {
      _libFuture = lf;
      _moviesFuture = mf;
      _content = _combine(lf, mf);
    });
    await _content;
    // Custom sections are separate queries, so they need refreshing too — a bulk
    // watch/favorite can move titles in or out of a saved filter.
    await _loadCustomSections();
  }

  /// Open the layout editor. It saves itself, reporting each stored layout through
  /// `onSaved`, so the Library follows along as the user edits.
  Future<void> _openCustomize() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => LibraryCustomizeSheet(
        sections: _sections,
        options: _filterOptions,
        save: _api.setLibrarySections,
        onSaved: _adoptSections,
      ),
    );
  }

  /// Take on a layout the customize sheet just persisted. Custom rails are only
  /// re-queried when a section that needs one actually changed — hiding a built-in
  /// or dragging a row shouldn't refetch every saved filter.
  void _adoptSections(List<LibrarySection> saved) {
    if (!mounted) return;
    String signature(List<LibrarySection> l) =>
        l.where((s) => s.isCustom && s.enabled).map((s) => '${s.id}:${s.filters}').join('|');
    final refetch = signature(saved) != signature(_sections);
    setState(() {
      _sections = saved;
      _customItems.removeWhere((id, _) => !saved.any((s) => s.id == id));
    });
    if (refetch) _loadCustomSections();
  }

  // Search within the user's library by name. Writes the query into `_f` (so it
  // composes with the filter) and, when it changes, resets the results grid. The
  // body switches to the flat filtered/searched view whenever `_f.isActive`.
  void _onSearchChanged() {
    final q = _searchCtrl.text.trim();
    setState(() {}); // refresh the clear button
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted || q == _f.query) return;
      setState(() {
        _f.query = q;
        _filterToken++;
      });
    });
  }

  void _clearSearch() {
    _searchCtrl.clear();
    _debounce?.cancel();
    if (_f.query.isNotEmpty) {
      setState(() {
        _f.query = '';
        _filterToken++;
      });
    } else {
      setState(() {});
    }
  }

  Future<void> _openShow(int seriesId) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ShowDetailScreen(seriesId: seriesId)));
  }

  @override
  Widget build(BuildContext context) {
    return SelectionScope(
      controller: _selection,
      child: Column(
        children: [
          _searchBar(),
          _filterBar(),
          Expanded(child: _filtering ? _filteredBody() : _libraryBody()),
          ListenableBuilder(
            listenable: _selection,
            builder: (_, _) => _selection.active
                ? BulkActionBar(controller: _selection, onChanged: _reloadContent, inLibrary: true)
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  // Row 1: search bar + filter icon (same layout as Discover). Row 2 (below) holds
  // the type toggles + the Library-only layout (rails/grid) toggle.
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
                hintText: t.searchYourShows,
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
              tooltip: t.filters,
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
    final layout = context.watch<SettingsController>().libraryLayout;
    Widget lbl(String s) => Text(s, maxLines: 1, softWrap: false, overflow: TextOverflow.fade);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Insets.lg, Insets.sm, Insets.lg, Insets.sm),
      child: Row(
        children: [
          Expanded(
            child: SegmentedButton<_Filter>(
              multiSelectionEnabled: true,
              emptySelectionAllowed: true,
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: [
                ButtonSegment(value: _Filter.series, label: lbl(t.typeSeries)),
                ButtonSegment(value: _Filter.anime, label: lbl(t.typeAnime)),
                ButtonSegment(value: _Filter.movies, label: lbl(t.typeMovies)),
              ],
              selected: _filter,
              onSelectionChanged: (s) {
                setState(() {
                  _filter = s;
                  _filterToken++; // also re-runs the filtered/searched view
                });
                // A mixed custom section's contents depend on the toggles, so its
                // rail has to be re-queried, not just re-rendered.
                _loadCustomSections();
              },
            ),
          ),
          const SizedBox(width: Insets.sm),
          // Library-only: rails vs grid layout.
          IconButton(
            tooltip: layout == LibraryLayout.rails ? t.gridView : t.carouselView,
            icon: Icon(layout == LibraryLayout.rails ? Icons.grid_view_rounded : Icons.view_carousel_rounded),
            onPressed: () => context.read<SettingsController>().toggleLibraryLayout(),
          ),
          // Which sections show, in what order, plus your own saved-filter rails.
          IconButton(
            tooltip: t.customizeLibrary,
            icon: const Icon(Icons.dashboard_customize_rounded),
            onPressed: _openCustomize,
          ),
        ],
      ),
    );
  }

  /// Flat, filtered view of the user's library (shown while a search or filter is
  /// active), with lazy pagination.
  Widget _filteredBody() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Insets.lg, 0, Insets.lg, Insets.sm),
          child: Row(
            children: [
              Builder(builder: (context) {
                final t = AppLocalizations.of(context);
                final sort = sortLabel(t, _f.sort);
                return Text(
                    _f.activeCount > 0
                        ? t.filteredSummary(_f.activeCount, sort)
                        : t.sortedBy(sort),
                    style: context.text.labelMedium?.copyWith(color: context.scheme.onSurfaceVariant));
              }),
              const Spacer(),
              TextButton.icon(
                icon: const Icon(Icons.close_rounded, size: 16),
                label: Text(AppLocalizations.of(context).clear),
                // Clear both the search and the facets → back to the rails.
                onPressed: () {
                  _debounce?.cancel();
                  _searchCtrl.clear();
                  setState(() {
                    _f.reset();
                    _f.query = '';
                    _filterToken++;
                  });
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: InfiniteGrid(
            resetKey: _filterToken,
            fetchPage: _filterPage,
            empty: MessageView(
                icon: Icons.search_off_rounded,
                message: _f.query.trim().isEmpty
                    ? AppLocalizations.of(context).filterNoMatch
                    : AppLocalizations.of(context).libraryNoMatchDiscover),
            itemBuilder: (context, r) => ShowCard(
              title: r.name ?? '—',
              imageUrl: r.imageUrl,
              subtitle: r.year?.toString(),
              // Library search: surface the viewer's rating + favorite, matching
              // the categorized library cards (Discover leaves these off).
              rating: r.rating,
              favorite: r.isFavorited,
              heroTag: '${r.kind}-${r.tvdbId}',
              selection: r.tvdbId == null
                  ? null
                  : SelItem(r.kind == 'movie' ? SelKind.movie : SelKind.series, r.tvdbId!, r.name ?? ''),
              onTap: r.tvdbId == null
                  ? null
                  : () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => r.kind == 'movie'
                          ? MovieDetailScreen(movieId: r.tvdbId!)
                          : ShowDetailScreen(seriesId: r.tvdbId!))),
            ),
          ),
        ),
      ],
    );
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
          if (snap.hasData) _lastContent = snap.data;
          // Keep showing the last content while a background refresh runs, so an
          // auto-reload (or pull-to-refresh) doesn't blank the library to a spinner.
          final data = snap.data ?? _lastContent;
          if (data == null) {
            if (snap.hasError) return _Scroll(child: ErrorView(message: '${snap.error}', onRetry: _reloadContent));
            return const _Scroll(child: LoadingView());
          }
          final (lib, movies) = data;

          // Series categories, filtered to the selected kinds: a show is kept if
          // it's anime and Anime is on, or non-anime and Series is on.
          List<LibraryShow> pick(List<LibraryShow> l) =>
              l.where((s) => (wantAnime && s.isAnime) || (wantSeries && !s.isAnime)).toList();
          // Build the sections in the user's chosen order. "Watch later" mixes
          // series (status = for_later) with watchlisted, not-yet-watched MOVIES so
          // both live together; watched/favorited movies get their own Movies
          // section.
          final sections = <(String, IconData, Color, int, Widget Function(int))>[];
          void addShows(LibCat cat, List<LibraryShow> shows) {
            if (shows.isNotEmpty) {
              sections.add((cat.title(t), cat.icon, cat.accent(context), shows.length, (j) => _libraryCard(shows[j])));
            }
          }

          final wlShows = pick(lib.forLater); // pick() already drops non-selected kinds
          final wlMovies =
              wantMovies ? movies.where((m) => m.watchlist && m.watchedCount == 0).toList() : const <LibraryMovie>[];
          final otherMovies =
              wantMovies ? movies.where((m) => !(m.watchlist && m.watchedCount == 0)).toList() : const <LibraryMovie>[];

          for (final section in _sections.where((s) => s.enabled)) {
            if (section.isCustom) {
              // A custom section pins one kind, so the type toggles hide it whole
              // rather than filtering inside it.
              if (!_customTypeVisible(section)) continue;
              final items = _customItems[section.id] ?? const <SearchResult>[];
              if (items.isNotEmpty) {
                sections.add((section.title ?? '', Icons.bookmark_rounded, context.scheme.tertiary, items.length,
                    (j) => _resultCard(items[j])));
              }
              continue;
            }
            switch (section.builtin) {
              case 'watching':
                addShows(builtinCats['watching']!, pick(lib.watching));
              case 'stale':
                addShows(builtinCats['stale']!, pick(lib.stale));
              case 'not_started':
                addShows(builtinCats['not_started']!, pick(lib.notStarted));
              case 'up_to_date':
                addShows(builtinCats['up_to_date']!, pick(lib.upToDate));
              case 'stopped':
                addShows(builtinCats['stopped']!, pick(lib.stopped));
              case 'for_later':
                if (wlShows.isNotEmpty || wlMovies.isNotEmpty) {
                  final wl = builtinCats['for_later']!;
                  sections.add((wl.title(t), wl.icon, wl.accent(context), wlShows.length + wlMovies.length,
                      (j) => j < wlShows.length ? _libraryCard(wlShows[j]) : _movieCard(wlMovies[j - wlShows.length])));
                }
              case 'movies':
                if (otherMovies.isNotEmpty) {
                  sections.add((t.typeMovies, Icons.theaters_rounded, context.scheme.tertiary, otherMovies.length,
                      (j) => _movieCard(otherMovies[j])));
                }
            }
          }

          if (sections.isEmpty) {
            // "Empty" has three very different causes, and saying "your library is
            // empty" when it holds hundreds of shows sends the user looking for the
            // wrong problem. Name the actual reason, and offer the way out.
            final enabled = _sections.where((s) => s.enabled).toList();
            final hiddenByType = enabled.isNotEmpty && enabled.every((s) => s.isCustom && !_customTypeVisible(s));
            if (enabled.isEmpty || hiddenByType) {
              return _Scroll(
                child: MessageView(
                  icon: hiddenByType ? Icons.filter_list_rounded : Icons.dashboard_customize_rounded,
                  message: hiddenByType ? t.libSectionsHiddenByType : t.libNoSections,
                  action: FilledButton.icon(
                    icon: const Icon(Icons.dashboard_customize_rounded),
                    label: Text(t.customizeLibrary),
                    onPressed: _openCustomize,
                  ),
                ),
              );
            }
            return _Scroll(child: MessageView(icon: Icons.video_library_rounded, message: t.libEmpty));
          }

          final grid = context.watch<SettingsController>().libraryLayout == LibraryLayout.grid;
          var section = 0; // running index for staggered reveal
          return CustomScrollView(
            // Persistent controller so a content reload (bulk action / auto-refresh)
            // keeps the scroll position instead of jumping to the top.
            controller: _bodyScroll,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              for (final (title, icon, accent, count, builder) in sections)
                ..._section(title, icon, accent, count, grid, section++, builder),
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
        rating: s.rating,
        // Progress bar replaces the "N watched" caption.
        heroTag: 'series-${s.seriesId}',
        selection: SelItem(SelKind.series, s.seriesId, s.name ?? ''),
        onTap: () => _openShow(s.seriesId),
      );

  /// A card in a custom section. These come from the filter endpoint, so they
  /// arrive as [SearchResult]s covering both series and movies — the section's own
  /// `type` decides which, and `kind` says where a tap should go.
  ShowCard _resultCard(SearchResult r) => ShowCard(
        title: r.name ?? '—',
        imageUrl: r.imageUrl,
        // The caption yields to the progress bar, but only when there IS one:
        // `ProgressStripe` hides itself at zero, so keying this on "progress was
        // computed" left an unstarted show with no bar AND no year — an emptier
        // card than before progress was added at all.
        subtitle: (r.progress ?? 0) > 0 ? null : r.year?.toString(),
        // ShowCard treats 0 as "no stripe", which is also the right rendering for
        // a result whose progress was never computed.
        progress: r.progress ?? 0,
        rating: r.rating,
        favorite: r.isFavorited,
        heroTag: '${r.kind}-${r.tvdbId}',
        selection: r.tvdbId == null
            ? null
            : SelItem(r.kind == 'movie' ? SelKind.movie : SelKind.series, r.tvdbId!, r.name ?? ''),
        onTap: r.tvdbId == null
            ? null
            : () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => r.kind == 'movie'
                    ? MovieDetailScreen(movieId: r.tvdbId!)
                    : ShowDetailScreen(seriesId: r.tvdbId!))),
      );

  ShowCard _movieCard(LibraryMovie m) => ShowCard(
        title: m.name ?? 'Movie ${m.movieId}',
        imageUrl: m.imageUrl,
        subtitle: m.year?.toString(),
        favorite: m.isFavorited,
        rating: m.rating,
        selection: SelItem(SelKind.movie, m.movieId, m.name ?? ''),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => MovieDetailScreen(movieId: m.movieId))),
      );
}


class _Scroll extends StatelessWidget {
  const _Scroll({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [SizedBox(height: MediaQuery.sizeOf(context).height * 0.28), child],
      );
}
