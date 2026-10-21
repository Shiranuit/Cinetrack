/// Mutable advanced-filter state, shared by Discover and the Library filter.
/// `toQuery()` maps directly onto the backend `/api/discover` + `/api/library/filter`
/// query params.
class AdvancedFilters {
  AdvancedFilters();

  /// The sort the user EXPLICITLY picked, or null if they haven't.
  ///
  /// Null is a real state, not a missing value: it's what lets each Library
  /// category use its own sort, and what browsing resolves to name A-Z
  /// (library) or popularity (Discover). Text searches use relevance. `toQuery` omits the parameter entirely,
  /// so the server sees the absence rather than a stand-in default.

  /// Free-text name search, combined with the facets below. In the Library it
  /// searches your tracked shows; in Discover it searches the whole catalog.
  String query = '';
  String type = 'series'; // series | movie | anime
  String? sort;
  bool sortDesc = true; // direction, only meaningful once a sort is picked
  bool includeLibrary = true; // Discover only: include shows already in your library (default on; off hides them)
  final Set<int> genresInc = {}, genresExc = {};
  final Set<int> tagsInc = {}, tagsExc = {};
  final Set<int> networks = {}, studios = {};
  final Set<String> statuses = {};

  /// Library-only: which Library buckets to keep (any-of) — "watching", "stale",
  /// "up_to_date", … Mirrors `tracking::state::STATES` on the server, and is what
  /// makes a duplicated built-in category reproduce the rail it came from.
  final Set<String> states = {};
  final Set<String> originalLanguages = {}, originalCountries = {};
  // Half-open, like the watch-history facets below: a bound left unset means "no
  // limit". The catalog holds an 11,863-episode series and a 713-season one, so a
  // range that always sent both bounds silently excluded everything past whatever
  // ceiling the slider happened to use.
  int? yearMin, yearMax;
  int? runtimeMin, runtimeMax;
  int? seasonsMin, seasonsMax;
  int? episodesMin, episodesMax;
  double? scoreMin;
  bool favoritesOnly = false; // library only

  // ---- library-only watch-history facets ----
  // Three distinct clocks, deliberately kept apart: when YOU last watched it,
  // when its LATEST EPISODE aired, and (via the 'updated' sort) when the catalog
  // record changed.
  // Half-open on purpose: each bound is independently nullable, so "watched in the
  // last 30 days" sends only a max and "untouched for over 90 days" sends only a
  // min. A RangeValues would always send both, and its slider ceiling would then
  // silently exclude everything beyond it (a show last watched two years ago is
  // NOT "within 0-365 days").
  int? watchedDaysMin, watchedDaysMax; // days since you last watched
  int? airedDaysMin, airedDaysMax; // days since its latest episode aired
  int? remainingMin, remainingMax; // aired episodes still unwatched
  double? progressMin, progressMax; // percent of aired episodes seen
  bool? caughtUp; // seen the latest aired episode
  bool? hasUpcoming; // a future-dated episode is scheduled

  /// Whether the library should switch from categorized rails to a flat, sorted
  /// results view — true only when a name search or a facet filter narrows the set.
  /// A sort alone does NOT switch views: it reorders WITHIN the categorized rails
  /// (the backend applies it per category), keeping the categories + layout toggle.
  bool get isActive => query.trim().isNotEmpty || activeCount > 0;

  int get activeCount =>
      (favoritesOnly ? 1 : 0) +
      (includeLibrary ? 0 : 1) + // on is the default; counts as active only when turned OFF
      genresInc.length +
      genresExc.length +
      tagsInc.length +
      tagsExc.length +
      networks.length +
      studios.length +
      statuses.length +
      states.length +
      originalLanguages.length +
      originalCountries.length +
      (yearMin != null || yearMax != null ? 1 : 0) +
      (runtimeMin != null || runtimeMax != null ? 1 : 0) +
      (seasonsMin != null || seasonsMax != null ? 1 : 0) +
      (episodesMin != null || episodesMax != null ? 1 : 0) +
      (scoreMin != null ? 1 : 0) +
      (watchedDaysMin != null || watchedDaysMax != null ? 1 : 0) +
      (airedDaysMin != null || airedDaysMax != null ? 1 : 0) +
      (remainingMin != null || remainingMax != null ? 1 : 0) +
      (progressMin != null || progressMax != null ? 1 : 0) +
      (caughtUp != null ? 1 : 0) +
      (hasUpcoming != null ? 1 : 0);

  void reset() {
    genresInc.clear();
    genresExc.clear();
    tagsInc.clear();
    tagsExc.clear();
    networks.clear();
    studios.clear();
    statuses.clear();
    states.clear();
    originalLanguages.clear();
    originalCountries.clear();
    yearMin = null;
    yearMax = null;
    runtimeMin = null;
    runtimeMax = null;
    seasonsMin = null;
    seasonsMax = null;
    episodesMin = null;
    episodesMax = null;
    scoreMin = null;
    watchedDaysMin = null;
    watchedDaysMax = null;
    airedDaysMin = null;
    airedDaysMax = null;
    remainingMin = null;
    remainingMax = null;
    progressMin = null;
    progressMax = null;
    caughtUp = null;
    hasUpcoming = null;
    favoritesOnly = false;
    includeLibrary = true;
    sort = null;
    sortDesc = true;
  }

  static String? _ids(Set<int> s) => s.isEmpty ? null : s.join(',');

  /// Non-null query params only.
  Map<String, String> toQuery() {
    final m = <String, String?>{
      'q': query.trim().isEmpty ? null : query.trim(),
      'type': type,
      // Both omitted when nothing was picked — their ABSENCE is the signal.
      'sort': sort,
      'dir': sort == null ? null : (sortDesc ? 'desc' : 'asc'),
      // Backend includes library shows by default; only send the flag to HIDE them.
      'include_library': includeLibrary ? null : 'false',
      'genres': _ids(genresInc),
      'exclude_genres': _ids(genresExc),
      'tags': _ids(tagsInc),
      'exclude_tags': _ids(tagsExc),
      'networks': _ids(networks),
      'studios': _ids(studios),
      'statuses': statuses.isEmpty ? null : statuses.join(','),
      'state': states.isEmpty ? null : states.join(','),
      'orig_langs': originalLanguages.isEmpty ? null : originalLanguages.join(','),
      'orig_countries': originalCountries.isEmpty ? null : originalCountries.join(','),
      'year_min': yearMin?.toString(),
      'year_max': yearMax?.toString(),
      'runtime_min': runtimeMin?.toString(),
      'runtime_max': runtimeMax?.toString(),
      'seasons_min': seasonsMin?.toString(),
      'seasons_max': seasonsMax?.toString(),
      'episodes_min': episodesMin?.toString(),
      'episodes_max': episodesMax?.toString(),
      'score_min': scoreMin?.toString(),
      'favorites': favoritesOnly ? 'true' : null,
      'watched_days_min': watchedDaysMin?.toString(),
      'watched_days_max': watchedDaysMax?.toString(),
      'aired_days_min': airedDaysMin?.toString(),
      'aired_days_max': airedDaysMax?.toString(),
      'remaining_min': remainingMin?.toString(),
      'remaining_max': remainingMax?.toString(),
      'progress_min': progressMin?.toString(),
      'progress_max': progressMax?.toString(),
      'caught_up': caughtUp?.toString(),
      'has_upcoming': hasUpcoming?.toString(),
    };
    m.removeWhere((_, v) => v == null);
    return m.cast<String, String>();
  }

  /// Rebuild filter state from a [toQuery] map — used to reopen a saved Library
  /// section in the filter sheet. Unknown keys and unparseable values are ignored
  /// rather than throwing: a section saved by a newer client must still be
  /// editable on an older one, just without the parts it doesn't understand.
  factory AdvancedFilters.fromQuery(Map<String, String> q) {
    final f = AdvancedFilters();
    void ids(String key, Set<int> into) {
      for (final part in (q[key] ?? '').split(',')) {
        final n = int.tryParse(part.trim());
        if (n != null) into.add(n);
      }
    }

    void names(String key, Set<String> into) {
      for (final part in (q[key] ?? '').split(',')) {
        if (part.trim().isNotEmpty) into.add(part.trim());
      }
    }

    f.query = q['q'] ?? '';
    f.type = q['type'] ?? 'series';
    f.sort = q['sort'];
    f.sortDesc = (q['dir'] ?? 'desc') != 'asc';
    f.includeLibrary = q['include_library'] != 'false';
    ids('genres', f.genresInc);
    ids('exclude_genres', f.genresExc);
    ids('tags', f.tagsInc);
    ids('exclude_tags', f.tagsExc);
    ids('networks', f.networks);
    ids('studios', f.studios);
    names('statuses', f.statuses);
    names('state', f.states);
    names('orig_langs', f.originalLanguages);
    names('orig_countries', f.originalCountries);
    // Each bound independently, so a half-open range survives the round trip.
    f.yearMin = int.tryParse(q['year_min'] ?? '');
    f.yearMax = int.tryParse(q['year_max'] ?? '');
    f.runtimeMin = int.tryParse(q['runtime_min'] ?? '');
    f.runtimeMax = int.tryParse(q['runtime_max'] ?? '');
    f.seasonsMin = int.tryParse(q['seasons_min'] ?? '');
    f.seasonsMax = int.tryParse(q['seasons_max'] ?? '');
    f.episodesMin = int.tryParse(q['episodes_min'] ?? '');
    f.episodesMax = int.tryParse(q['episodes_max'] ?? '');
    f.scoreMin = double.tryParse(q['score_min'] ?? '');
    f.favoritesOnly = q['favorites'] == 'true';
    // Each bound independently: a saved section may carry only one of them.
    f.watchedDaysMin = int.tryParse(q['watched_days_min'] ?? '');
    f.watchedDaysMax = int.tryParse(q['watched_days_max'] ?? '');
    f.airedDaysMin = int.tryParse(q['aired_days_min'] ?? '');
    f.airedDaysMax = int.tryParse(q['aired_days_max'] ?? '');
    f.remainingMin = int.tryParse(q['remaining_min'] ?? '');
    f.remainingMax = int.tryParse(q['remaining_max'] ?? '');
    f.progressMin = double.tryParse(q['progress_min'] ?? '');
    f.progressMax = double.tryParse(q['progress_max'] ?? '');
    // Absent means "no constraint", which is different from an explicit false.
    f.caughtUp = q.containsKey('caught_up') ? q['caught_up'] == 'true' : null;
    f.hasUpcoming = q.containsKey('has_upcoming') ? q['has_upcoming'] == 'true' : null;
    return f;
  }
}
