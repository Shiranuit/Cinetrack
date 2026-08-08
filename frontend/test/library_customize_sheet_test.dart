import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/api/models.dart';
import 'package:frontend/design/app_theme.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:frontend/widgets/library_customize_sheet.dart';

/// Pump a sheet the way `showModalBottomSheet` does, at a given screen width, so
/// layout errors surface here instead of in the running app.
Widget host(Widget child, {String locale = 'en'}) => MaterialApp(
      locale: Locale(locale),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: AppTheme.dark(),
      home: Scaffold(body: Builder(builder: (context) => child)),
    );

void main() {
  _resetLayoutTests();
  _autoSaveTests();
  testWidgets('the sheet lists every built-in, and only those', (tester) async {
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(LibraryCustomizeSheet(
      sections: defaultLibrarySections(),
      save: (l) async => l,
    )));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(Switch), findsNWidgets(kBuiltinLibrarySections.length));
  });
}

/// The sheet persists itself: no Save button, every change debounced into a write,
/// and nothing lost if it's closed inside the debounce window.
void _autoSaveTests() {
  /// Records each save and echoes the layout back with ids filled in, the way the
  /// server does for rows it just created.
  ({List<List<LibrarySection>> calls, LibrarySectionsSaver save}) recorder({Object? throws}) {
    final calls = <List<LibrarySection>>[];
    return (
      calls: calls,
      save: (sections) async {
        calls.add(List.of(sections));
        if (throws != null) throw throws;
        return [
          for (var i = 0; i < sections.length; i++)
            sections[i].id == null
                ? LibrarySection(id: 'server-$i', builtin: sections[i].builtin, enabled: sections[i].enabled)
                : sections[i],
        ];
      },
    );
  }

  Future<void> pumpSheet(WidgetTester tester, LibrarySectionsSaver save,
      {void Function(List<LibrarySection>)? onSaved}) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(LibraryCustomizeSheet(
      sections: defaultLibrarySections(),
      save: save,
      onSaved: onSaved,
    )));
    await tester.pumpAndSettle();
  }

  testWidgets('there is no Save button', (tester) async {
    await pumpSheet(tester, recorder().save);
    expect(find.widgetWithText(TextButton, 'Save'), findsNothing);
  });

  testWidgets('toggling a section saves it without any further interaction', (tester) async {
    final r = recorder();
    List<LibrarySection>? reported;
    await pumpSheet(tester, r.save, onSaved: (s) => reported = s);

    await tester.tap(find.byType(Switch).first);
    await tester.pump();
    expect(r.calls, isEmpty, reason: 'debounced, not fired on the gesture itself');

    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(r.calls, hasLength(1));
    expect(r.calls.single.first.enabled, isFalse);
    expect(reported, isNotNull, reason: 'the Library is told about the stored layout');
  });

  testWidgets('a burst of changes collapses into one write', (tester) async {
    final r = recorder();
    await pumpSheet(tester, r.save);

    for (final i in [0, 1, 2]) {
      await tester.tap(find.byType(Switch).at(i));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(r.calls, hasLength(1), reason: 'three toggles, one request');
    expect(r.calls.single.where((s) => !s.enabled), hasLength(3));
  });

  testWidgets('closing inside the debounce window still saves', (tester) async {
    final r = recorder();
    await pumpSheet(tester, r.save);

    await tester.tap(find.byType(Switch).first);
    await tester.pump(const Duration(milliseconds: 50));
    expect(r.calls, isEmpty);

    // Tear the sheet down before the debounce fires.
    await tester.pumpWidget(host(const SizedBox.shrink()));
    await tester.pumpAndSettle();

    expect(r.calls, hasLength(1), reason: 'dispose flushes the pending change');
    expect(r.calls.single.first.enabled, isFalse);
  });

  testWidgets('a failed save surfaces and leaves the edit on screen', (tester) async {
    final r = recorder(throws: Exception('nope'));
    await pumpSheet(tester, r.save);

    await tester.tap(find.byType(Switch).first);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(r.calls, hasLength(1));
    expect(find.textContaining('nope'), findsOneWidget);
    // The user's change is still shown — reverting under them would be worse.
    final firstSwitch = tester.widget<Switch>(find.byType(Switch).first);
    expect(firstSwitch.value, isFalse);
  });
}

/// "Reset layout" restores the stock arrangement — every category in its default
/// order and shown, including ones the saved layout had dropped entirely.
void _resetLayoutTests() {
  final scrambled = [
    const LibrarySection(id: 'b1', builtin: 'movies', enabled: false),
    const LibrarySection(id: 'b2', builtin: 'watching', enabled: false),
    const LibrarySection(id: 'b3', builtin: 'stale'),
  ];

  Future<List<LibrarySection>?> tapReset(WidgetTester tester, {required bool confirm}) async {
    tester.view.physicalSize = const Size(500, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    List<LibrarySection>? saved;
    await tester.pumpWidget(host(LibraryCustomizeSheet(
      sections: [...scrambled],
      save: (l) async {
        saved = List.of(l);
        return l;
      },
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Reset layout'));
    await tester.pumpAndSettle();
    // The confirm action is the outlined one; cancel is the filled one.
    await tester.tap(find.widgetWithText(confirm ? OutlinedButton : FilledButton, confirm ? 'Reset layout' : 'Cancel'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    return saved;
  }

  testWidgets('restores every built-in, in order and shown', (tester) async {
    final saved = await tapReset(tester, confirm: true);
    expect(saved, isNotNull);

    expect(saved!.map((s) => s.builtin), kBuiltinLibrarySections,
        reason: 'default order restored, including the ones that were missing');
    expect(saved.every((s) => s.enabled), isTrue, reason: 'and all shown again');
  });

  testWidgets('keeps existing ids so the reset is an edit, not a rebuild', (tester) async {
    final saved = await tapReset(tester, confirm: true);
    final byKey = {for (final s in saved!) s.builtin: s.id};
    expect(byKey['movies'], 'b1');
    expect(byKey['watching'], 'b2');
    expect(byKey['stale'], 'b3');
  });

  testWidgets('cancelling changes nothing', (tester) async {
    final saved = await tapReset(tester, confirm: false);
    expect(saved, isNull, reason: 'no save, so nothing was touched');
  });
}
