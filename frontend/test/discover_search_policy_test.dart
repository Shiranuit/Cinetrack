import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:frontend/api/api_client.dart';
import 'package:frontend/api/filters.dart';
import 'package:frontend/api/models.dart';
import 'package:frontend/design/app_theme.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:frontend/screens/discover_screen.dart';
import 'package:frontend/state/library_membership.dart';
import 'package:frontend/state/settings.dart';
import 'package:frontend/widgets/filter_sheet.dart';

class SearchApi extends ApiClient {
  final delayed = Completer<void>();

  @override
  Future<FilterOptions> filterOptions({bool library = false}) async => const FilterOptions();

  @override
  Future<List<SearchResult>> filteredSearch(AdvancedFilters f,
      {bool library = false, String? langs, String? type, int limit = 60,
      int offset = 0, void Function(bool exactOnly)? onSearchMode}) async {
    final query = f.query;
    if (query == 'old') await delayed.future;
    onSearchMode?.call(query == 'the' || query == 'old');
    if (type == 'movie' || query.isEmpty || offset > 0) return [];
    return [SearchResult(tvdbId: 1, kind: 'series', name: query == 'old' ? 'Old result' : query == 'the' ? 'The' : 'The Office')];
  }
}

class RankedSearchApi extends SearchApi {
  @override
  Future<List<SearchResult>> filteredSearch(AdvancedFilters f,
      {bool library = false, String? langs, String? type, int limit = 60,
      int offset = 0, void Function(bool exactOnly)? onSearchMode}) async {
    onSearchMode?.call(false);
    if (f.query.isEmpty || offset > 0) return [];
    return [type == 'movie'
      ? const SearchResult(tvdbId: 2, kind: 'movie', name: 'Exact movie', relevance: 1000000)
      : const SearchResult(tvdbId: 1, kind: 'series', name: 'Partial series', relevance: 400000)];
  }
}

Future<void> pumpDiscover(WidgetTester tester, SearchApi api) async {
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<ApiClient>.value(value: api),
      ChangeNotifierProvider(create: (_) => SettingsController()),
      ChangeNotifierProvider(create: (_) => LibraryMembership()),
    ],
    child: MaterialApp(
      theme: AppTheme.dark(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(body: DiscoverScreen()),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('an exact movie precedes a partial series in the mixed discovery grid', (tester) async {
    await pumpDiscover(tester, RankedSearchApi());
    await tester.enterText(find.byType(TextField), 'match');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    final titles = tester.widgetList<Text>(find.byType(Text)).map((t) => t.data)
        .where((t) => t == 'Exact movie' || t == 'Partial series').toList();
    expect(titles, ['Exact movie', 'Partial series']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('search explains relevance while retaining the chosen browse sort', (tester) async {
    final filters = AdvancedFilters()..query = 'match'..sort = 'year'..sortDesc = false;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: FilterSheet(filters: filters, options: const FilterOptions())),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('Search results are ordered by title match'), findsOneWidget);
    expect(find.text('Popular'), findsNothing);
    expect(filters.sort, 'year');
    expect(filters.sortDesc, isFalse);
  });

  testWidgets('exact matches remain visible with guidance, and normal queries clear it', (tester) async {
    final api = SearchApi();
    await pumpDiscover(tester, api);
    await tester.enterText(find.byType(TextField), 'the');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(find.text('The'), findsOneWidget);
    expect(find.textContaining('Add another word'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'the office');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(find.text('The Office'), findsOneWidget);
    expect(find.textContaining('Add another word'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an older pending query cannot replace current cards or its search mode', (tester) async {
    final api = SearchApi();
    await pumpDiscover(tester, api);
    await tester.enterText(find.byType(TextField), 'old');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.enterText(find.byType(TextField), 'the office');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    api.delayed.complete();
    await tester.pumpAndSettle();
    expect(find.text('The Office'), findsOneWidget);
    expect(find.text('Old result'), findsNothing);
    expect(find.textContaining('Add another word'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
