import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/api/models.dart';
import 'package:frontend/design/app_theme.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:frontend/widgets/activity_tile.dart';

/// Unix seconds `d` days / `h` hours ago.
int ago({int days = 0, int hours = 0, int minutes = 0}) =>
    DateTime.now().subtract(Duration(days: days, hours: hours, minutes: minutes)).millisecondsSinceEpoch ~/ 1000;

Future<void> pumpTile(WidgetTester tester, ActivityItem item, {VoidCallback? onTap}) =>
    tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: ActivityTile(item: item, onTap: onTap)),
    ));

void main() {
  testWidgets('an episode entry shows the series, SxxExx · title and when', (tester) async {
    await pumpTile(
      tester,
      ActivityItem(
        id: 1,
        entityType: 'episode',
        seriesId: 10,
        name: 'Severance',
        episodeId: 101,
        episodeName: "Trojan's Horse",
        seasonNumber: 2,
        episodeNumber: 5,
        watchedAt: ago(hours: 2),
      ),
    );
    await tester.pump();

    expect(find.text('Severance'), findsOneWidget);
    expect(find.text("S2E5 · Trojan's Horse"), findsOneWidget);
    expect(find.text('2h ago'), findsOneWidget);
    // Not a rewatch → no rewatch marker.
    expect(find.text('Rewatched'), findsNothing);
  });

  testWidgets('a rewatch is marked', (tester) async {
    await pumpTile(
      tester,
      ActivityItem(
        id: 2,
        entityType: 'episode',
        seriesId: 10,
        name: 'Severance',
        seasonNumber: 1,
        episodeNumber: 1,
        isRewatch: true,
        watchedAt: ago(minutes: 5),
      ),
    );
    await tester.pump();

    expect(find.text('Rewatched'), findsOneWidget);
    expect(find.text('5m ago'), findsOneWidget);
  });

  testWidgets('a movie entry shows the title with no episode line', (tester) async {
    await pumpTile(
      tester,
      ActivityItem(
        id: 3,
        entityType: 'movie',
        movieId: 500,
        name: 'Arrival',
        watchedAt: ago(days: 3),
      ),
    );
    await tester.pump();

    expect(find.text('Arrival'), findsOneWidget);
    expect(find.text('3d ago'), findsOneWidget);
    expect(find.textContaining('S'), findsNothing, reason: 'movies have no season/episode line');
  });

  testWidgets('a missing title falls back to the id, and tapping fires onTap', (tester) async {
    var taps = 0;
    await pumpTile(
      tester,
      ActivityItem(id: 4, entityType: 'movie', movieId: 500, watchedAt: ago(minutes: 0)),
      onTap: () => taps++,
    );
    await tester.pump();

    expect(find.text('Movie 500'), findsOneWidget);
    expect(find.text('Just now'), findsOneWidget);

    await tester.tap(find.byType(ActivityTile));
    expect(taps, 1);
  });

  testWidgets('a watch older than a week shows an absolute date', (tester) async {
    await pumpTile(
      tester,
      ActivityItem(id: 5, entityType: 'movie', movieId: 1, name: 'Old One', watchedAt: ago(days: 40)),
    );
    await tester.pump();

    expect(find.textContaining('ago'), findsNothing);
  });

  // Long titles + the widest translations on the narrowest phone: a RenderFlex
  // overflow throws in debug, so a clean pump means the row still fits.
  for (final locale in [const Locale('en'), const Locale('fr'), const Locale('de'), const Locale('pt')]) {
    testWidgets('a long entry fits a 320px screen (${locale.languageCode})', (tester) async {
      tester.view.physicalSize = const Size(320, 400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark(),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ActivityTile(
            item: ActivityItem(
              id: 6,
              entityType: 'episode',
              seriesId: 12,
              name: 'A Very Long Show Title That Should Ellipsize Cleanly',
              episodeName: 'An equally long episode name that must not overflow the row',
              seasonNumber: 12,
              episodeNumber: 134,
              isRewatch: true,
              watchedAt: ago(days: 2),
            ),
          ),
        ),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }
}
