import 'package:flutter_test/flutter_test.dart';

import 'package:flutter/material.dart';
import 'package:frontend/api/filters.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:frontend/widgets/filter_sheet.dart';
import 'package:frontend/api/models.dart';
import 'package:frontend/widgets/library_categories.dart';

/// A custom Library section stores its filter as the query-param map the filter
/// endpoint speaks, so `toQuery` → `fromQuery` has to round-trip: what the user
/// picked when they created the category is what they see when they reopen it.
void main() {
  _mergeTests();
  _multiKindTests();
  _watchHistoryFacetTests();
  _progressTests();
  _cardCaptionTests();
  _sortHelpTests();
  _openRangeTests();
  _rangeLabelTests();
  _presetSyncTests();
  group('AdvancedFilters round trip', () {
    test('preserves every facet a saved section can carry', () {
      final original = AdvancedFilters(defaultSort: 'my_rating')
        ..query = 'cowboy'
        ..type = 'anime'
        ..sort = 'year'
        ..sortDesc = false
        ..favoritesOnly = true
        ..yearMin = 1990
        ..yearMax = 1999
        ..seasonsMin = 1
        ..seasonsMax = 5
        ..episodesMin = 10
        ..episodesMax = 26
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
      expect(back.yearMin, 1990);
      expect(back.yearMax, 1999);
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
        'year_min': '1990', // a lower bound with no upper one is now representable
        'future_facet': 'whatever',
      });
      expect(back.type, 'movie');
      expect(back.genresInc, {12, 45});
      expect(back.yearMin, 1990, reason: 'a half-open range survives the round trip');
      expect(back.yearMax, isNull);
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



/// The watch-history facets must survive the save/reopen cycle, since a saved
/// category is stored as a query map and reopened in the filter sheet.
void _watchHistoryFacetTests() {
  group('watch-history facets round trip', () {
    test('ranges and tri-state flags survive toQuery -> fromQuery', () {
      final f = AdvancedFilters(defaultSort: 'my_rating')
        ..watchedDaysMax = 30
        ..airedDaysMax = 7
        ..remainingMin = 1
        ..remainingMax = 20
        ..progressMax = 80
        ..caughtUp = false
        ..hasUpcoming = true
        ..sort = 'remaining';

      final q = f.toQuery();
      expect(q['watched_days_max'], '30');
      expect(q['remaining_min'], '1');
      expect(q['caught_up'], 'false');
      expect(q['has_upcoming'], 'true');
      expect(q['sort'], 'remaining');

      expect(q.containsKey('watched_days_min'), isFalse,
          reason: 'a half-open range must not assert a lower bound it does not have');

      final back = AdvancedFilters.fromQuery(q, defaultSort: 'my_rating');
      expect(back.watchedDaysMax, 30);
      expect(back.watchedDaysMin, isNull);
      expect(back.remainingMin, 1);
      expect(back.remainingMax, 20);
      expect(back.caughtUp, isFalse);
      expect(back.hasUpcoming, isTrue);
      expect(back.toQuery(), q);
    });

    test('an absent flag means "no constraint", not false', () {
      final back = AdvancedFilters.fromQuery(const {'type': 'series'});
      expect(back.caughtUp, isNull, reason: 'unset must not become an explicit false');
      expect(back.hasUpcoming, isNull);
      expect(back.activeCount, 0);
      expect(back.toQuery().containsKey('caught_up'), isFalse);
    });

    test('each facet counts toward the active-filter badge', () {
      final f = AdvancedFilters(defaultSort: 'my_rating')..watchedDaysMax = 30;
      expect(f.activeCount, 1);
      f.watchedDaysMin = 5; // same facet, still one badge
      expect(f.activeCount, 1);
      f.caughtUp = false;
      expect(f.activeCount, 2);
    });

    test('the "seen recently" view is expressible as a saved section', () {
      final f = AdvancedFilters(defaultSort: 'my_rating')
        ..watchedDaysMax = 30
        ..sort = 'remaining'
        ..sortDesc = true;
      f.statuses.add('Continuing');

      final section = LibrarySection(title: 'Seen recently', filters: {...f.toQuery(), 'type': 'series'});
      expect(section.filters['watched_days_max'], '30');
      expect(section.filters['statuses'], 'Continuing');
      expect(section.filters['sort'], 'remaining');
      expect(section.kinds, {'series'});
    });
  });
}

/// Custom rails draw the same cards as the built-in ones, progress bar included —
/// which needs the counts on the search row, not just on `LibraryShow`.
void _progressTests() {
  group('SearchResult.progress', () {
    test('matches LibraryShow.progress for the same counts', () {
      const r = SearchResult(tvdbId: 1, kind: 'series', totalEpisodes: 10, seenEpisodes: 4);
      expect(r.progress, closeTo(0.4, 1e-9));
    });

    test('is null when the query did not compute it', () {
      const r = SearchResult(tvdbId: 1, kind: 'series');
      expect(r.progress, isNull, reason: 'not computed is not the same as 0%');
    });

    test('a show with no aired episodes is 0, not a divide by zero', () {
      const r = SearchResult(tvdbId: 1, kind: 'series', totalEpisodes: 0, seenEpisodes: 0);
      expect(r.progress, 0.0);
    });

    test('clamps when watch rows outnumber the catalog (dead episode ids)', () {
      const r = SearchResult(tvdbId: 1, kind: 'series', totalEpisodes: 5, seenEpisodes: 8);
      expect(r.progress, 1.0);
    });

    test('parses the counts the batch endpoint sends', () {
      final r = SearchResult.fromJson(const {
        'tvdb_id': 1, 'kind': 'series', 'total_episodes': 12, 'seen_episodes': 3,
      });
      expect(r.progress, closeTo(0.25, 1e-9));
    });
  });
}

/// Every sort chip carries an explanation — "Episodes left" (a count) and
/// "Progress" (a percentage) are otherwise indistinguishable from their labels.
void _sortHelpTests() {
  testWidgets('every offered sort has a distinct, non-placeholder explanation', (tester) async {
    late AppLocalizations t;
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(builder: (context) {
        t = AppLocalizations.of(context);
        return const SizedBox.shrink();
      }),
    ));

    final offered = [...kSortKeys, 'my_rating', ...kLibrarySortKeys];
    final seen = <String, String>{};
    for (final key in offered) {
      final help = sortHelp(t, key);
      expect(help, isNotEmpty);
      expect(help, isNot(key), reason: '$key falls through to the raw key instead of a description');
      expect(seen.containsKey(help), isFalse, reason: '$key reuses the text of ${seen[help]}');
      seen[help] = key;
    }
  });

  testWidgets('the count/percentage distinction is actually spelled out', (tester) async {
    late AppLocalizations t;
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(builder: (context) {
        t = AppLocalizations.of(context);
        return const SizedBox.shrink();
      }),
    ));
    expect(sortHelp(t, 'remaining').toLowerCase(), contains('count'));
    expect(sortHelp(t, 'progress').toLowerCase(), contains('percentage'));
    // The owner-vs-you distinction survives in another user's library.
    expect(sortHelp(t, 'my_rating', othersLibrary: true), isNot(sortHelp(t, 'my_rating')));
  });

  testWidgets('French labels that read alike are told apart by their tooltips', (tester) async {
    late AppLocalizations t;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('fr'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(builder: (context) {
        t = AppLocalizations.of(context);
        return const SizedBox.shrink();
      }),
    ));

    // "Les plus longs" (episode LENGTH) vs "Épisodes" (episode COUNT) — the labels
    // give no hint which is which.
    expect(sortLabel(t, 'runtime'), 'Les plus longs');
    expect(sortHelp(t, 'runtime'), contains('Durée'));
    expect(sortHelp(t, 'episodes'), contains('Nombre total'));
    expect(sortHelp(t, 'runtime'), isNot(sortHelp(t, 'episodes')));

    // And the pair that prompted this: a count vs a percentage.
    expect(sortHelp(t, 'remaining'), contains('nombre'));
    expect(sortHelp(t, 'progress'), contains('pourcentage'));
  });

  testWidgets('the sort chips are actually wrapped in tooltips', (tester) async {
    tester.view.physicalSize = const Size(500, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: FilterSheet(
          filters: AdvancedFilters(defaultSort: 'my_rating'),
          options: const FilterOptions(),
          showFavorites: true, // library scope, so the watch-history sorts appear
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final messages = tester
        .widgetList<Tooltip>(find.byType(Tooltip))
        .map((w) => w.message)
        .whereType<String>()
        .toSet();
    // The rendered tooltips must be the sort explanations, not some other widget's.
    late AppLocalizations t;
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(builder: (context) {
        t = AppLocalizations.of(context);
        return const SizedBox.shrink();
      }),
    ));
    for (final key in ['remaining', 'progress', 'runtime', 'episodes', 'last_watched']) {
      expect(messages, contains(sortHelp(t, key)), reason: 'no tooltip for the $key sort');
    }
  });
}

/// The catalog's tail is long — an 11,863-episode series, a 713-season one — so a
/// range that always sent both bounds silently excluded anything past the slider's
/// ceiling. Parking a handle at an extreme must mean "no bound".
void _openRangeTests() {
  group('open-ended ranges', () {
    test('a lone lower bound reaches past any slider ceiling', () {
      final f = AdvancedFilters()..episodesMin = 1000;
      final q = f.toQuery();
      expect(q['episodes_min'], '1000');
      expect(q.containsKey('episodes_max'), isFalse,
          reason: 'an 11,863-episode series must not be excluded by an implied ceiling');

      final back = AdvancedFilters.fromQuery(q);
      expect(back.episodesMin, 1000);
      expect(back.episodesMax, isNull);
    });

    test('seasons and years behave the same way', () {
      final f = AdvancedFilters()
        ..seasonsMin = 40
        ..yearMax = 1980;
      final q = f.toQuery();
      expect(q.containsKey('seasons_max'), isFalse, reason: 'a 713-season show still qualifies');
      expect(q.containsKey('year_min'), isFalse, reason: 'no implied floor on release year');
      expect(q['year_max'], '1980');
    });

    test('each range still counts as one active filter, either bound', () {
      final f = AdvancedFilters()..episodesMax = 12;
      expect(f.activeCount, 1);
      f.episodesMin = 1;
      expect(f.activeCount, 1);
      f.seasonsMin = 2;
      expect(f.activeCount, 2);
    });

    test('clearing a range removes both bounds', () {
      final f = AdvancedFilters()
        ..episodesMin = 1
        ..episodesMax = 12;
      f.reset();
      expect(f.toQuery().keys.where((k) => k.startsWith('episodes_')), isEmpty);
      expect(f.activeCount, 0);
    });
  });
}

/// The bounds control has to say what the filter asserts on its collapsed header —
/// otherwise an applied bound is invisible until expanded, and an unset facet looks
/// like a constraint that isn't there.
void _rangeLabelTests() {
  Future<void> pumpSheet(WidgetTester tester, AdvancedFilters f) async {
    tester.view.physicalSize = const Size(500, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: FilterSheet(filters: f, options: const FilterOptions(), showFavorites: true)),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('bounds are typed, not dragged', (tester) async {
    await pumpSheet(tester, AdvancedFilters());
    expect(find.byType(RangeSlider), findsNothing);
    expect(find.textContaining('0–1000'), findsNothing, reason: 'a ceiling that was never applied');
  });

  testWidgets('a lone lower bound reads as open-ended on the header', (tester) async {
    await pumpSheet(tester, AdvancedFilters()..episodesMin = 1000);
    expect(find.text('\u2265 1000'), findsOneWidget, reason: 'an 11,863-episode series matches this');
  });

  testWidgets('a closed range still reads as a range', (tester) async {
    await pumpSheet(tester, AdvancedFilters()
      ..episodesMin = 10
      ..episodesMax = 26);
    expect(find.text('10\u201326'), findsOneWidget);
  });

  testWidgets('an upper bound alone reads as a ceiling', (tester) async {
    await pumpSheet(tester, AdvancedFilters()..episodesMax = 12);
    expect(find.text('\u2264 12'), findsOneWidget);
  });

  testWidgets('typing a bound applies it, and clearing the field restores "any"', (tester) async {
    final f = AdvancedFilters();
    await pumpSheet(tester, f);

    // "Episodes" is also a sort chip, so target the section header specifically.
    final section = find.widgetWithText(ExpansionTile, 'Episodes');
    await tester.tap(find.descendant(of: section, matching: find.text('Episodes')).last);
    await tester.pumpAndSettle();

    final fields = find.descendant(of: section, matching: find.byType(TextField));
    await tester.enterText(fields.first, '1000');
    await tester.pumpAndSettle();
    expect(f.episodesMin, 1000);
    expect(f.episodesMax, isNull, reason: 'an empty max must stay unbounded');

    // Emptying the field means "no bound", not zero.
    await tester.enterText(fields.first, '');
    await tester.pumpAndSettle();
    expect(f.episodesMin, isNull);
    expect(f.activeCount, 0);
  });
}

/// Runtime keeps its three presets inside the bounds section — which means the
/// fields must follow changes made from OUTSIDE them (a preset chip, or Reset),
/// or the model moves on while the text stays behind.
void _presetSyncTests() {
  Future<AdvancedFilters> pump(WidgetTester tester, {AdvancedFilters? filters}) async {
    tester.view.physicalSize = const Size(500, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final f = filters ?? AdvancedFilters();
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: FilterSheet(filters: f, options: const FilterOptions(), showFavorites: true)),
    ));
    await tester.pumpAndSettle();
    return f;
  }

  Finder runtimeSection() => find.widgetWithText(ExpansionTile, 'Episode / runtime length');

  /// The sheet is a lazy ListView, so a section below the fold isn't built yet.
  /// Dragged explicitly rather than via scrollUntilVisible, which trips over the
  /// nested scrollables a DraggableScrollableSheet introduces.
  Future<void> scrollTo(WidgetTester tester, String title) async {
    for (var i = 0; i < 25 && find.text(title).evaluate().isEmpty; i++) {
      await tester.drag(find.byType(ListView).last, const Offset(0, -300));
      await tester.pumpAndSettle();
    }
    expect(find.text(title), findsWidgets, reason: 'never scrolled to "$title"');
  }

  testWidgets('the runtime buckets became a bounds section, presets intact', (tester) async {
    await pump(tester);
    await scrollTo(tester, 'Episode / runtime length');
    expect(runtimeSection(), findsOneWidget);
    await tester.tap(find.descendant(of: runtimeSection(), matching: find.text('Episode / runtime length')).last);
    await tester.pumpAndSettle();
    expect(find.text('< 30m'), findsOneWidget, reason: 'the quick path survives the conversion');
    expect(find.descendant(of: runtimeSection(), matching: find.byType(TextField)), findsNWidgets(2));
  });

  testWidgets('a preset chip writes the fields', (tester) async {
    final f = await pump(tester);
    await scrollTo(tester, 'Episode / runtime length');
    await tester.tap(find.descendant(of: runtimeSection(), matching: find.text('Episode / runtime length')).last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('30–60m'));
    await tester.pumpAndSettle();

    expect(f.runtimeMin, 30);
    expect(f.runtimeMax, 60);
    final fields = tester.widgetList<TextField>(
      find.descendant(of: runtimeSection(), matching: find.byType(TextField)),
    ).toList();
    expect(fields[0].controller?.text, '30', reason: 'the field must follow the chip');
    expect(fields[1].controller?.text, '60');
    expect(find.text('30–60'), findsOneWidget, reason: 'and the header summary too');
  });

  testWidgets('Reset empties the fields, not just the model', (tester) async {
    final f = await pump(tester, filters: AdvancedFilters()..episodesMin = 42);
    final section = find.widgetWithText(ExpansionTile, 'Episodes');
    expect(
      tester.widgetList<TextField>(find.descendant(of: section, matching: find.byType(TextField))).first.controller?.text,
      '42',
    );

    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();

    expect(f.episodesMin, isNull);
    expect(
      tester.widgetList<TextField>(find.descendant(of: section, matching: find.byType(TextField))).first.controller?.text,
      '',
      reason: 'a stale 42 would show a filter that is no longer applied',
    );
  });
}

/// A custom rail's card must never end up with neither a year nor a progress bar.
/// `ProgressStripe` hides itself at zero, so an unstarted show (0 of N watched,
/// which the server now reports as 0 rather than NULL) has no bar — and the caption
/// has to survive, or the card shows nothing but the poster.
void _cardCaptionTests() {
  group('rail card caption vs progress bar', () {
    test('an unstarted show keeps its year, because it gets no stripe', () {
      const r = SearchResult(tvdbId: 1, kind: 'series', name: 'Unstarted', year: 1999, totalEpisodes: 12, seenEpisodes: 0);
      expect(r.progress, 0.0);
      // What `_resultCard` decides: caption shown only when no stripe will render.
      expect((r.progress ?? 0) > 0, isFalse, reason: 'no stripe, so the year must show');
    });

    test('a partly-watched show yields the caption to its stripe', () {
      const r = SearchResult(tvdbId: 1, kind: 'series', name: 'Half', year: 1999, totalEpisodes: 12, seenEpisodes: 6);
      expect((r.progress ?? 0) > 0, isTrue);
    });

    test('a row without computed progress keeps its year', () {
      const r = SearchResult(tvdbId: 1, kind: 'movie', name: 'Film', year: 1999);
      expect(r.progress, isNull);
      expect((r.progress ?? 0) > 0, isFalse, reason: 'movies never carry progress and must show the year');
    });

    test('series and movies in one rail agree on when the caption shows', () {
      // The inconsistency this guards: a mixed rail where movies showed a year and
      // unstarted series showed nothing at all.
      const unstartedSeries = SearchResult(tvdbId: 1, kind: 'series', year: 2001, totalEpisodes: 8, seenEpisodes: 0);
      const movie = SearchResult(tvdbId: 2, kind: 'movie', year: 2001);
      expect((unstartedSeries.progress ?? 0) > 0, (movie.progress ?? 0) > 0);
    });
  });
}
