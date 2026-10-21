import 'models.dart';

/// Matches the backend's relevance, popularity, id ordering. Kind resolves the
/// final tie between independent id spaces when series and movies are combined.
int compareSearchResults(SearchResult a, SearchResult b) {
  var order = (b.relevance ?? 0).compareTo(a.relevance ?? 0);
  if (order != 0) return order;
  final ap = a.searchPopularity, bp = b.searchPopularity;
  order = ap == null
      ? (bp == null ? 0 : 1)
      : bp == null
      ? -1
      : bp.compareTo(ap);
  if (order != 0) return order;
  order = (b.tvdbId ?? 0).compareTo(a.tvdbId ?? 0);
  return order != 0 ? order : (a.kind ?? '').compareTo(b.kind ?? '');
}

typedef SearchPageFetcher =
    Future<List<SearchResult>> Function(String kind, int offset, int limit);

/// Merge sorted source streams before cutting pages. Sorting each concatenated
/// page alone would allow a better match from a later source page to appear late.
/// Create a new pager whenever the query, languages, kinds or facets change.
class RankedSearchPager {
  RankedSearchPager({
    required List<String> kinds,
    required this.fetch,
    this.batchSize = 60,
  }) : _sources = [for (final kind in kinds) _Source(kind)];

  final SearchPageFetcher fetch;
  final int batchSize;
  final List<_Source> _sources;
  // Keeping emitted rows also makes retries safe if a source fails mid-page.
  final List<SearchResult> _emitted = [];

  Future<List<SearchResult>> page(int offset, int limit) async {
    final end = offset + limit;
    while (_emitted.length < end) {
      // Every nonempty stream needs a head before selecting the next global hit.
      await Future.wait(
        _sources.where((s) => s.needsFetch).map((s) async {
          final rows = await fetch(s.kind, s.offset, batchSize);
          s.rows = rows;
          s.index = 0;
          s.offset += rows.length;
          s.done = rows.length < batchSize;
        }),
      );
      _Source? best;
      for (final source in _sources) {
        if (source.index >= source.rows.length) continue;
        if (best == null || compareSearchResults(source.head, best.head) < 0) {
          best = source;
        }
      }
      if (best == null) break;
      _emitted.add(best.head);
      best.index++;
    }
    if (offset >= _emitted.length) return [];
    return _emitted.sublist(offset, end.clamp(0, _emitted.length));
  }
}

class _Source {
  _Source(this.kind);
  final String kind;
  List<SearchResult> rows = [];
  int index = 0, offset = 0;
  bool done = false;
  bool get needsFetch => !done && index >= rows.length;
  SearchResult get head => rows[index];
}
