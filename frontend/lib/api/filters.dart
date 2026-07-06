import 'package:flutter/material.dart';

/// Mutable advanced-filter state, shared by Discover and the Library filter.
/// `toQuery()` maps directly onto the backend `/api/discover` + `/api/library/filter`
/// query params.
class AdvancedFilters {
  /// Free-text name search, combined with the facets below. In the Library it
  /// searches your tracked shows; in Discover it searches the whole catalog.
  String query = '';
  String type = 'series'; // series | movie | anime
  String sort = 'popularity';
  bool sortDesc = true; // sort direction; false = ascending
  bool includeLibrary = false; // Discover only: also show shows already in your library
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
      (includeLibrary ? 1 : 0) +
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
    includeLibrary = false;
    sort = 'popularity';
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
      'include_library': includeLibrary ? 'true' : null,
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
}
