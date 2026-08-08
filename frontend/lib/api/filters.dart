import 'package:flutter/material.dart';

/// Mutable advanced-filter state, shared by Discover and the Library filter.
/// `toQuery()` maps directly onto the backend `/api/discover` + `/api/library/filter`
/// query params.
class AdvancedFilters {
  AdvancedFilters({this.defaultSort = 'popularity'}) : sort = defaultSort;

  /// Initial sort key, also the one restored by [reset]. Discover uses
  /// 'popularity'; the Library passes 'my_rating' (Your rating).
  final String defaultSort;

  /// Free-text name search, combined with the facets below. In the Library it
  /// searches your tracked shows; in Discover it searches the whole catalog.
  String query = '';
  String type = 'series'; // series | movie | anime
  String sort;
  bool sortDesc = true; // sort direction; false = ascending
  bool includeLibrary = true; // Discover only: include shows already in your library (default on; off hides them)
  final Set<int> genresInc = {}, genresExc = {};
  final Set<int> tagsInc = {}, tagsExc = {};
  final Set<int> networks = {}, studios = {};
  final Set<String> statuses = {};
  final Set<String> originalLanguages = {}, originalCountries = {};
  RangeValues? years;
  int? runtimeMin, runtimeMax;
  RangeValues? seasons;
  RangeValues? episodes;
  double? scoreMin;
  bool favoritesOnly = false; // library only

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
      originalLanguages.length +
      originalCountries.length +
      (years != null ? 1 : 0) +
      (runtimeMin != null || runtimeMax != null ? 1 : 0) +
      (seasons != null ? 1 : 0) +
      (episodes != null ? 1 : 0) +
      (scoreMin != null ? 1 : 0);

  void reset() {
    genresInc.clear();
    genresExc.clear();
    tagsInc.clear();
    tagsExc.clear();
    networks.clear();
    studios.clear();
    statuses.clear();
    originalLanguages.clear();
    originalCountries.clear();
    years = null;
    runtimeMin = null;
    runtimeMax = null;
    seasons = null;
    episodes = null;
    scoreMin = null;
    favoritesOnly = false;
    includeLibrary = true;
    sort = defaultSort;
    sortDesc = true;
  }

  static String? _ids(Set<int> s) => s.isEmpty ? null : s.join(',');

  /// Non-null query params only.
  Map<String, String> toQuery() {
    final m = <String, String?>{
      'q': query.trim().isEmpty ? null : query.trim(),
      'type': type,
      'sort': sort,
      'dir': sortDesc ? 'desc' : 'asc',
      // Backend includes library shows by default; only send the flag to HIDE them.
      'include_library': includeLibrary ? null : 'false',
      'genres': _ids(genresInc),
      'exclude_genres': _ids(genresExc),
      'tags': _ids(tagsInc),
      'exclude_tags': _ids(tagsExc),
      'networks': _ids(networks),
      'studios': _ids(studios),
      'statuses': statuses.isEmpty ? null : statuses.join(','),
      'orig_langs': originalLanguages.isEmpty ? null : originalLanguages.join(','),
      'orig_countries': originalCountries.isEmpty ? null : originalCountries.join(','),
      'year_min': years?.start.round().toString(),
      'year_max': years?.end.round().toString(),
      'runtime_min': runtimeMin?.toString(),
      'runtime_max': runtimeMax?.toString(),
      'seasons_min': seasons?.start.round().toString(),
      'seasons_max': seasons?.end.round().toString(),
      'episodes_min': episodes?.start.round().toString(),
      'episodes_max': episodes?.end.round().toString(),
      'score_min': scoreMin?.toString(),
      'favorites': favoritesOnly ? 'true' : null,
    };
    m.removeWhere((_, v) => v == null);
    return m.cast<String, String>();
  }

  /// Rebuild filter state from a [toQuery] map — used to reopen a saved Library
  /// section in the filter sheet. Unknown keys and unparseable values are ignored
  /// rather than throwing: a section saved by a newer client must still be
  /// editable on an older one, just without the parts it doesn't understand.
  factory AdvancedFilters.fromQuery(Map<String, String> q, {String defaultSort = 'popularity'}) {
    final f = AdvancedFilters(defaultSort: defaultSort);
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

    // A range survives a round trip only if both ends are present — half a range
    // isn't representable in RangeValues, so drop it rather than invent a bound.
    RangeValues? range(String minKey, String maxKey) {
      final lo = double.tryParse(q[minKey] ?? ''), hi = double.tryParse(q[maxKey] ?? '');
      return (lo != null && hi != null) ? RangeValues(lo, hi) : null;
    }

    f.query = q['q'] ?? '';
    f.type = q['type'] ?? 'series';
    f.sort = q['sort'] ?? defaultSort;
    f.sortDesc = (q['dir'] ?? 'desc') != 'asc';
    f.includeLibrary = q['include_library'] != 'false';
    ids('genres', f.genresInc);
    ids('exclude_genres', f.genresExc);
    ids('tags', f.tagsInc);
    ids('exclude_tags', f.tagsExc);
    ids('networks', f.networks);
    ids('studios', f.studios);
    names('statuses', f.statuses);
    names('orig_langs', f.originalLanguages);
    names('orig_countries', f.originalCountries);
    f.years = range('year_min', 'year_max');
    f.runtimeMin = int.tryParse(q['runtime_min'] ?? '');
    f.runtimeMax = int.tryParse(q['runtime_max'] ?? '');
    f.seasons = range('seasons_min', 'seasons_max');
    f.episodes = range('episodes_min', 'episodes_max');
    f.scoreMin = double.tryParse(q['score_min'] ?? '');
    f.favoritesOnly = q['favorites'] == 'true';
    return f;
  }
}
