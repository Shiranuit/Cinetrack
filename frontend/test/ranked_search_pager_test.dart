import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/api/models.dart';
import 'package:frontend/api/ranked_search_pager.dart';

SearchResult hit(
  int id,
  int score, {
  String kind = 'series',
  double? popularity,
}) => SearchResult(
  tvdbId: id,
  kind: kind,
  relevance: score,
  searchPopularity: popularity,
);

void main() {
  test(
    'mixed pages are globally ranked even when one source fills multiple pages',
    () async {
      final corpus = {
        'series': [for (var i = 10; i >= 1; i--) hit(i, i * 10)],
        'movie': [hit(90, 95, kind: 'movie'), hit(40, 45, kind: 'movie')],
      };
      final calls = <(String, int)>[];
      final pager = RankedSearchPager(
        kinds: corpus.keys.toList(),
        batchSize: 2,
        fetch: (kind, offset, limit) async {
          calls.add((kind, offset));
          return corpus[kind]!.skip(offset).take(limit).toList();
        },
      );
      final all = <SearchResult>[];
      for (var offset = 0; offset < 15; offset += 3) {
        all.addAll(await pager.page(offset, 3));
      }
      expect(all.map((r) => r.tvdbId), [10, 90, 9, 8, 7, 6, 5, 40, 4, 3, 2, 1]);
      expect(calls.where((c) => c.$1 == 'series').map((c) => c.$2), [
        0,
        2,
        4,
        6,
        8,
        10,
      ]);
      expect(calls.where((c) => c.$1 == 'movie').map((c) => c.$2), [0, 2]);
      expect(await pager.page(15, 3), isEmpty);
    },
  );

  test(
    'a failed source can be retried without skipping rows already merged',
    () async {
      var fail = true;
      final pager = RankedSearchPager(
        kinds: ['series', 'movie'],
        batchSize: 2,
        fetch: (kind, offset, limit) async {
          if (kind == 'movie') return [hit(1, 1, kind: 'movie')];
          if (offset == 2 && fail) {
            fail = false;
            throw StateError('temporary source failure');
          }
          return [
            hit(10, 10),
            hit(9, 9),
            hit(8, 8),
            hit(7, 7),
          ].skip(offset).take(limit).toList();
        },
      );
      await expectLater(pager.page(0, 3), throwsStateError);
      expect((await pager.page(0, 3)).map((r) => r.tvdbId), [10, 9, 8]);
      expect((await pager.page(3, 3)).map((r) => r.tvdbId), [7, 1]);
    },
  );

  test(
    'ties use popularity then id and kind; null popularity follows zero',
    () {
      final rows = [
        hit(1, 20),
        hit(9, 10),
        hit(2, 10, popularity: 0),
        hit(3, 10, popularity: 0),
        hit(3, 10, popularity: 0, kind: 'movie'),
        hit(1, 10, popularity: 5),
      ]..sort(compareSearchResults);
      expect(rows.map((r) => (r.kind, r.tvdbId)), [
        ('series', 1),
        ('series', 1),
        ('movie', 3),
        ('series', 3),
        ('series', 2),
        ('series', 9),
      ]);
      final decoded = SearchResult.fromJson({
        'tvdb_id': 1,
        'relevance': 1000000,
        'search_popularity': 7,
      });
      expect(decoded.relevance, 1000000);
      expect(decoded.searchPopularity, 7.0);
    },
  );
}
