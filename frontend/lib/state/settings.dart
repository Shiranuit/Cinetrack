import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App-wide preferences: theme mode (dark by default) and preferred content
/// languages (used for search translation ordering).
/// How the library groups shows: horizontal carousels (rails) or a grid per category.
enum LibraryLayout { rails, grid }

class SettingsController extends ChangeNotifier {
  ThemeMode themeMode = ThemeMode.dark;
  List<String> languages = ['eng'];
  LibraryLayout libraryLayout = LibraryLayout.rails;

  /// UI locale derived from the user's primary content language. Returns null for
  /// languages the app UI isn't translated into (Flutter then falls back to the
  /// first supported locale, English).
  Locale? get locale => switch (languages.isEmpty ? 'eng' : languages.first) {
        'eng' => const Locale('en'),
        'fra' => const Locale('fr'),
        'spa' => const Locale('es'),
        'deu' => const Locale('de'),
        'ita' => const Locale('it'),
        'por' => const Locale('pt'),
        'jpn' => const Locale('ja'),
        'kor' => const Locale('ko'),
        'zho' => const Locale('zh'),
        _ => null,
      };

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    themeMode = switch (prefs.getString('themeMode')) {
      'light' => ThemeMode.light,
      'system' => ThemeMode.system,
      _ => ThemeMode.dark,
    };
    final langs = prefs.getStringList('languages');
    if (langs != null && langs.isNotEmpty) languages = langs;
    libraryLayout = prefs.getString('libraryLayout') == 'grid' ? LibraryLayout.grid : LibraryLayout.rails;
    notifyListeners();
  }

  Future<void> setLibraryLayout(LibraryLayout layout) async {
    libraryLayout = layout;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('libraryLayout', layout.name);
  }

  Future<void> toggleLibraryLayout() =>
      setLibraryLayout(libraryLayout == LibraryLayout.rails ? LibraryLayout.grid : LibraryLayout.rails);

  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('themeMode', mode.name);
  }

  Future<void> toggleTheme() =>
      setThemeMode(themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark);

  bool get isDark => themeMode != ThemeMode.light;

  Future<void> setLanguages(List<String> langs) async {
    languages = langs.isEmpty ? ['eng'] : langs;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('languages', languages);
  }

  String get langsParam => languages.join(',');
}
