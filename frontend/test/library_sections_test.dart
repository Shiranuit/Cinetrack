import 'package:flutter/material.dart' show RangeValues;
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/api/filters.dart';
import 'package:frontend/api/models.dart';
import 'package:frontend/widgets/library_categories.dart';

/// A custom Library section stores its filter as the query-param map the filter
/// endpoint speaks, so `toQuery` → `fromQuery` has to round-trip: what the user
/// picked when they created the category is what they see when they reopen it.
void main() {
  _mergeTests();
  _multiKindTests();
  group('AdvancedFilters round trip', () {
    test('preserves every facet a saved section can carry', () {
      final original = AdvancedFilters(defaultSort: 'my_rating')
        ..query = 'cowboy'
        ..type = 'anime'
        ..sort = 'year'
        ..sortDesc = false
        ..favoritesOnly = true
        ..years = const RangeValues(1990, 1999)
        ..seasons = const RangeValues(1, 5)
        ..episodes = const RangeValues(10, 26)
        ..runtimeMin = 20
        ..runtimeMax = 30
        ..scoreMin = 7.5;
      original.genresInc.addAll([12, 45]);
      original.genresExc.add(99);
      original.tagsInc.add(7);
      original.networks.addAll([1, 2]);
      original.studios.add(3);
      original.statuses.add('Continuing');
      original.originalLanguages.add('jpn');
      original.originalCountries.add('jpn');

      final back = AdvancedFilters.fromQuery(original.toQuery(), defaultSort: 'my_rating');

      expect(back.toQuery(), original.toQuery());
      expect(back.query, 'cowboy');
      expect(back.type, 'anime');
      expect(back.sortDesc, isFalse);
      expect(back.genresInc, {12, 45});
      expect(back.genresExc, {99});
      expect(back.statuses, {'Continuing'});
      expect(back.originalLanguages, {'jpn'});
      expect(back.years, const RangeValues(1990, 1999));
      expect(back.scoreMin, 7.5);
      expect(back.activeCount, original.activeCount);
    });

    test('an empty filter is a valid section — everything, in one order', () {
      final empty = AdvancedFilters(defaultSort: 'my_rating');
      final back = AdvancedFilters.fromQuery(empty.toQuery(), defaultSort: 'my_rating');
      expect(back.activeCount, 0);
      expect(back.sort, 'my_rating');
    });

    test('ignores keys and values it cannot parse instead of throwing', () {
      // A section saved by a newer client must stay editable on an older one.
      final back = AdvancedFilters.fromQuery(const {
        'type': 'movie',
        'genres': '12,not-a-number,45',
        'year_min': '1990', // no matching max -> not a representable range
        'future_facet': 'whatever',
      });
      expect(back.type, 'movie');
      expect(back.genresInc, {12, 45});
      expect(back.years, isNull);
    });
  });

  group('LibrarySection', () {
    test('defaults mirror the server-side built-ins', () {
      final defaults = defaultLibrarySections();
      expect(defaults.map((s) => s.builtin), kBuiltinLibrarySections);
      expect(defaults.every((s) => s.enabled && !s.isCustom), isTrue);
    });

    test('serializes built-in and custom sections in the shapes the server accepts', () {
      // A built-in carries no title/filters...
      final builtin = const LibrarySection(builtin: 'watching').toJson();
      expect(builtin['builtin'], 'watching');
      expect(builtin['title'], isNull);
      expect(builtin['filters'], isNull);

      // ...and a custom section carries no builtin.
      final custom = const LibrarySection(
        id: 'abc',
        title: '90s sci-fi',
        filters: {'type': 'series', 'year_max': '1999'},
      ).toJson();
      expect(custom['builtin'], isNull);
      expect(custom['title'], '90s sci-fi');
      expect(custom['filters'], {'type': 'series', 'year_max': '1999'});
      expect(custom['id'], 'abc', reason: 'editing must update in place, not create a new row');
    });

    test('round-trips through fromJson', () {
      const section = LibrarySection(id: 'x', title: 'Rewatch', filters: {'favorites': 'true'}, enabled: false);
      final back = LibrarySection.fromJson(section.toJson().cast<String, dynamic>());
      expect(back.id, 'x');
      expect(back.title, 'Rewatch');
      expect(back.filters, {'favorites': 'true'});
      expect(back.enabled, isFalse);
      expect(back.isCustom, isTrue);
    });
  });
}

/// A custom section's saved filter is merged with the Library's live filter state
/// when its rail is fetched — see `mergedSectionFilters`.
void _mergeTests() {
  group('mergedSectionFilters', () {
    const section = LibrarySection(
      id: 's1',
      title: 'Comfort anime',
      filters: {'type': 'anime', 'sort': 'year', 'dir': 'asc', 'favorites': 'true'},
    );

    test('leaves the section alone while the Library sort is untouched', () {
      final f = AdvancedFilters(defaultSort: 'my_rating');
      final merged = mergedSectionFilters(section, f);
      expect(merged['sort'], 'year', reason: 'the sort saved with the section still applies');
      expect(merged['dir'], 'asc');
      expect(merged['favorites'], 'true');
    });

    test('the Library sort wins once the user picks one', () {
      final f = AdvancedFilters(defaultSort: 'my_rating')..sort = 'name';
      final merged = mergedSectionFilters(section, f);
      expect(merged['sort'], 'name');
      expect(merged['dir'], 'desc');
    });

    test('a reversed direction counts as picking a sort', () {
      final f = AdvancedFilters(defaultSort: 'my_rating')..sortDesc = false;
      expect(mergedSectionFilters(section, f)['dir'], 'asc');
      expect(mergedSectionFilters(section, f)['sort'], 'my_rating');
    });

    test('global facets narrow the section', () {
      final f = AdvancedFilters(defaultSort: 'my_rating')..scoreMin = 8.0;
      f.genresInc.add(12);
      final merged = mergedSectionFilters(section, f);
      expect(merged['score_min'], '8.0');
      expect(merged['genres'], '12');
      expect(merged['favorites'], 'true', reason: 'the section keeps its own facets too');
    });

    test('never overrides the kind the section pinned', () {
      final f = AdvancedFilters(defaultSort: 'my_rating')..type = 'movie';
      expect(mergedSectionFilters(section, f)['type'], 'anime');
    });
  });
}

/// A category can span Series, Anime and Movies at once. `search_db` takes one kind
/// per call, so the client fans out and merges — these pin that resolution.
void _multiKindTests() {
  SearchResult res(String name, {String kind = 'series', bool anime = false, int? year, int? rating}) =>
      SearchResult(tvdbId: name.hashCode, kind: kind, name: name, year: year, rating: rating, isAnime: anime);

  group('sectionQueryKinds', () {
    test('series absorbs anime — querying both would return every anime twice', () {
      expect(sectionQueryKinds({'series', 'anime'}), ['series']);
      expect(sectionQueryKinds({'series'}), ['series']);
    });

    test('anime is queried on its own only when series is not selected', () {
      expect(sectionQueryKinds({'anime'}), ['anime']);
      expect(sectionQueryKinds({'anime', 'movie'}), ['anime', 'movie']);
    });

    test('movies are always their own query', () {
      expect(sectionQueryKinds({'movie'}), ['movie']);
      expect(sectionQueryKinds({'series', 'anime', 'movie'}), ['series', 'movie']);
    });
  });

  group('mergeSectionResults', () {
    test('drops anime the section did not ask for', () {
      // A `series` query carries anime whether or not it was requested.
      final series = [res('Breaking Bad'), res('Cowboy Bebop', anime: true)];
      final merged = mergeSectionResults([series], {'series'});
      expect(merged.map((r) => r.name), ['Breaking Bad']);
    });

    test('keeps anime when the section covers it', () {
      final series = [res('Breaking Bad'), res('Cowboy Bebop', anime: true)];
      expect(mergeSectionResults([series], {'series', 'anime'}).length, 2);
      expect(mergeSectionResults([series], {'anime'}).map((r) => r.name), ['Cowboy Bebop']);
    });

    test('interleaves kinds by a sort the rows can actually be compared on', () {
      final series = [res('B-show', year: 2020), res('C-show', year: 2000)];
      final movies = [res('A-movie', kind: 'movie', year: 2010)];
      final merged = mergeSectionResults([series, movies], {'series', 'movie'}, sort: 'year');
      expect(merged.map((r) => r.year), [2020, 2010, 2000], reason: 'newest first across both kinds');

      final asc = mergeSectionResults([series, movies], {'series', 'movie'}, sort: 'name', desc: false);
      expect(asc.map((r) => r.name), ['A-movie', 'B-show', 'C-show']);
    });

    test('keeps per-kind blocks for sorts the rows cannot express', () {
      // 'popularity' isn't carried on a search row, so inventing an order would be
      // worse than leaving the server's per-kind ordering intact.
      final series = [res('S1'), res('S2')];
      final movies = [res('M1', kind: 'movie')];
      final merged = mergeSectionResults([series, movies], {'series', 'movie'}, sort: 'popularity');
      expect(merged.map((r) => r.name), ['S1', 'S2', 'M1']);
    });
  });

  group('LibrarySection.kinds', () {
    test('parses a comma list, defaulting to series', () {
      expect(const LibrarySection(title: 'x', filters: {'type': 'series,movie'}).kinds, {'series', 'movie'});
      expect(const LibrarySection(title: 'x', filters: {'type': 'movie'}).kinds, {'movie'});
      // A section saved before multi-kind support, or with no type at all.
      expect(const LibrarySection(title: 'x', filters: {}).kinds, {'series'});
    });
  });
}
