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
  _duplicateTests();
  _resetLayoutTests();
  _autoSaveTests();
  _kindRoundTrip();
  testWidgets('the category editor lays out on a narrow screen', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(const LibraryCategoryEditor(options: FilterOptions())));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Category name'), findsOneWidget);
  });

  testWidgets('the category editor lays out on a wide screen', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(const LibraryCategoryEditor(options: FilterOptions())));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('editing a saved category shows its name and stays laid out', (tester) async {
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(const LibraryCategoryEditor(
      section: LibrarySection(id: 'a', title: '90s sci-fi', filters: {'type': 'movie', 'year_max': '1999'}),
      options: FilterOptions(),
    )));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('90s sci-fi'), findsOneWidget);
  });

  testWidgets('the customize sheet lists built-ins and custom sections', (tester) async {
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final sections = [
      ...defaultLibrarySections(),
      const LibrarySection(id: 'c1', title: 'Comfort anime', filters: {'type': 'anime'}),
    ];
    await tester.pumpWidget(host(LibraryCustomizeSheet(
      sections: sections,
      options: const FilterOptions(),
      save: (l) async => l,
    )));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Comfort anime'), findsOneWidget);
    expect(find.byType(Switch), findsNWidgets(sections.length));
  });
}

/// The editor owns the kind chips (not the filter sheet's single-valued `type`),
/// so saving must write them back as the comma list the section stores.
void _kindRoundTrip() {
  testWidgets('a multi-kind category survives edit and save', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    LibrarySection? saved;
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: AppTheme.dark(),
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () async {
              saved = await showModalBottomSheet<LibrarySection>(
                context: context,
                isScrollControlled: true,
                builder: (_) => const LibraryCategoryEditor(
                  section: LibrarySection(id: 'c1', title: 'Mixed', filters: {'type': 'series,movie'}),
                  options: FilterOptions(),
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    expect(saved!.kinds, {'series', 'movie'}, reason: 'the chips, not the filter sheet, own `type`');
    expect(saved!.id, 'c1', reason: 'editing updates in place');
    expect(saved!.title, 'Mixed');
  });
}

/// The sheet persists itself: no Save button, every change debounced into a write,
/// and nothing lost if it's closed inside the debounce window.
void _autoSaveTests() {
  /// Records each save and echoes the layout back with ids filled in, the way the
  /// server does for newly-created sections.
  ({List<List<LibrarySection>> calls, LibrarySectionsSaver save}) recorder({Object? throws}) {
    final calls = <List<LibrarySection>>[];
    return (
      calls: calls,
      save: (sections) async {
        calls.add(List.of(sections));
        if (throws != null) throw throws;
        return [
          for (var i = 0; i < sections.length; i++)
            sections[i].isCustom && sections[i].id == null
                ? LibrarySection(
                    id: 'server-$i',
                    title: sections[i].title,
                    filters: sections[i].filters,
                    enabled: sections[i].enabled)
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
      options: const FilterOptions(),
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

/// Duplicate belongs to custom categories, not built-ins: a built-in is computed
/// rather than configured, so there's nothing to copy that the filter sheet can't
/// already express.
void _duplicateTests() {
  Future<void> pumpSheet(WidgetTester tester, List<LibrarySection> sections) async {
    tester.view.physicalSize = const Size(500, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(LibraryCustomizeSheet(
      sections: sections,
      options: const FilterOptions(),
      save: (l) async => l,
    )));
    await tester.pumpAndSettle();
  }

  testWidgets('built-in rows offer neither copy nor delete', (tester) async {
    await pumpSheet(tester, defaultLibrarySections());
    expect(find.byIcon(Icons.copy_rounded), findsNothing);
    expect(find.byIcon(Icons.delete_outline_rounded), findsNothing);
    // They can still be reordered and hidden.
    expect(find.byType(Switch), findsNWidgets(kBuiltinLibrarySections.length));
  });

  testWidgets('a custom row offers both, and copying keeps the filter', (tester) async {
    final sections = [
      const LibrarySection(builtin: 'watching'),
      const LibrarySection(id: 'c1', title: 'Comfort anime', filters: {'type': 'anime', 'state': 'stale'}),
    ];
    List<LibrarySection>? saved;
    tester.view.physicalSize = const Size(500, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(LibraryCustomizeSheet(
      sections: sections,
      options: const FilterOptions(),
      save: (l) async {
        saved = List.of(l);
        return l;
      },
    )));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.copy_rounded), findsOneWidget, reason: 'only the custom row');
    await tester.tap(find.byIcon(Icons.copy_rounded));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(saved, isNotNull, reason: 'duplicating is a change, so it auto-saves');
    final copies = saved!.where((s) => s.isCustom).toList();
    expect(copies, hasLength(2));
    expect(copies[1].filters, copies[0].filters, reason: 'the copy carries the same filter');
    expect(copies[1].id, isNull, reason: 'a copy is a NEW section, not an edit of the original');
    expect(copies[1].title, contains('Comfort anime'));
    expect(saved!.indexOf(copies[1]), saved!.indexOf(copies[0]) + 1, reason: 'inserted right after');
  });
}

/// "Reset layout" restores the stock arrangement. It HIDES custom categories
/// rather than deleting them — a custom category can hold a lot of tuning, and the
/// sheet saves immediately, so an irreversible reset would be a trap.
void _resetLayoutTests() {
  final scrambled = [
    const LibrarySection(id: 'b1', builtin: 'movies', enabled: false),
    const LibrarySection(id: 'c1', title: 'Comfort anime', filters: {'type': 'anime'}),
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
      options: const FilterOptions(),
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

    final builtins = saved!.where((s) => !s.isCustom).toList();
    expect(builtins.map((s) => s.builtin), kBuiltinLibrarySections,
        reason: 'default order restored, including the ones that were missing');
    expect(builtins.every((s) => s.enabled), isTrue, reason: 'and all shown again');
  });

  testWidgets('hides custom categories without deleting them', (tester) async {
    final saved = await tapReset(tester, confirm: true);
    final custom = saved!.where((s) => s.isCustom).toList();
    expect(custom, hasLength(1), reason: 'still there');
    expect(custom.single.title, 'Comfort anime');
    expect(custom.single.filters, {'type': 'anime'}, reason: 'its filter is intact');
    expect(custom.single.enabled, isFalse, reason: 'hidden, so it can be switched back on');
    expect(custom.single.id, 'c1', reason: 'same section, not a replacement');
  });

  testWidgets('keeps built-in ids so the reset is an edit, not a rebuild', (tester) async {
    final saved = await tapReset(tester, confirm: true);
    final byKey = {for (final s in saved!.where((s) => !s.isCustom)) s.builtin: s.id};
    expect(byKey['movies'], 'b1');
    expect(byKey['watching'], 'b2');
    expect(byKey['stale'], 'b3');
  });

  testWidgets('cancelling changes nothing', (tester) async {
    final saved = await tapReset(tester, confirm: false);
    expect(saved, isNull, reason: 'no save, so nothing was touched');
  });
}
