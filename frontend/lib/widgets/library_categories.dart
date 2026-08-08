import 'package:flutter/material.dart';

import '../api/filters.dart';
import '../api/models.dart';
import '../design/app_colors.dart';
import '../l10n/app_localizations.dart';

/// Presentation for the Library's built-in categories, shared by the Library
/// screen and the customize sheet.
typedef AccentFn = Color Function(BuildContext);

class LibCat {
  const LibCat(this.title, this.icon, this.accent);
  final String Function(AppLocalizations) title;
  final IconData icon;
  final AccentFn accent;
}

/// Presentation for each built-in category, keyed by the section key the server
/// stores (`kBuiltinLibrarySections`). 'movies' is rendered from the movie list
/// rather than a `Library` bucket, so it has no entry here.
final builtinCats = <String, LibCat>{
  'watching': LibCat((t) => t.catWatching, Icons.play_circle_rounded, (c) => c.scheme.primary),
  'up_to_date': LibCat((t) => t.catUpToDate, Icons.check_circle_rounded, (c) => c.colors.seen),
  'stale': LibCat((t) => t.catStale, Icons.history_rounded, (c) => c.colors.warning),
  'not_started': LibCat((t) => t.catNotStarted, Icons.playlist_add_rounded, (c) => c.scheme.secondary),
  'stopped': LibCat((t) => t.catStopped, Icons.pause_circle_rounded, (c) => c.scheme.onSurfaceVariant),
  'for_later': LibCat((t) => t.watchLater, Icons.schedule_rounded, (c) => c.scheme.tertiary),
};


/// A custom section's saved filter with the Library's live filter state layered on
/// top: the section defines its own set, the screen's filter narrows it.
///
/// Two things are deliberately NOT taken from the global state:
///
/// * `type` — the section pins its own kind, and the screen's type toggles hide a
///   section whole rather than filtering inside it.
/// * the sort, unless the user actually chose one. The Library's default sort would
///   otherwise permanently override the sort saved with the section, making
///   per-section sort pointless; once you pick a sort in the filter sheet, the
///   whole Library follows it, rails included.
Map<String, String> mergedSectionFilters(LibrarySection section, AdvancedFilters f) {
  final global = f.toQuery()..remove('type');
  if (f.sort == f.defaultSort && f.sortDesc) {
    global.remove('sort');
    global.remove('dir');
  }
  return {...section.filters, ...global};
}

/// Backend queries needed to cover a section's kinds. `search_db` takes exactly one
/// kind, so a multi-kind section fans out — but "series" ALREADY includes anime
/// (anime is Japanese-language series, same table), so asking for both would return
/// every anime twice. Series therefore absorbs anime, exactly as the Library's own
/// type toggles do in `_backendKinds`.
List<String> sectionQueryKinds(Set<String> kinds) => [
      if (kinds.contains('series')) 'series' else if (kinds.contains('anime')) 'anime',
      if (kinds.contains('movie')) 'movie',
    ];

/// Fold the per-kind responses of a multi-kind section into one rail.
///
/// Two jobs. First, drop anime the section didn't ask for: a `series` query carries
/// it regardless, so "Series + Movies" would otherwise quietly include anime.
///
/// Second, restore the ordering. Each response is sorted server-side, but
/// concatenating them would group all series ahead of all movies. Where the sort key
/// is one the rows actually carry (name, year, your rating) they're re-sorted into a
/// single sequence; for keys the DTO doesn't expose — popularity, runtime, season and
/// episode counts — the per-kind blocks are kept in order, since inventing a
/// comparison would order them wrongly rather than not at all.
List<SearchResult> mergeSectionResults(
  List<List<SearchResult>> perKind,
  Set<String> kinds, {
  String? sort,
  bool desc = true,
}) {
  final wantAnime = kinds.contains('anime');
  final wantSeries = kinds.contains('series');
  final merged = [
    for (final list in perKind)
      for (final r in list)
        if (r.kind == 'movie' || (r.isAnime ? wantAnime : wantSeries)) r,
  ];
  if (perKind.length < 2) return merged;

  final Comparable<Object>? Function(SearchResult)? key = switch (sort) {
    'name' => (r) => (r.name ?? '').toLowerCase() as Comparable<Object>,
    'year' => (r) => (r.year ?? 0) as Comparable<Object>,
    'my_rating' => (r) => (r.rating ?? 0) as Comparable<Object>,
    _ => null,
  };
  if (key == null) return merged;

  merged.sort((a, b) {
    final ka = key(a), kb = key(b);
    if (ka == null || kb == null) return 0;
    return desc ? kb.compareTo(ka) : ka.compareTo(kb);
  });
  return merged;
}

/// Key for one (section, kind) pair in a batched library-filter request. The
/// server echoes it back verbatim, so it only has to be unique within a batch and
/// splittable by the client that made it.
String sectionBatchKey(String sectionId, String kind) => '$sectionId|$kind';
