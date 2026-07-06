import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';

/// App-wide preferences: theme mode (dark by default) and preferred content
/// languages (used for search translation ordering).
/// How the library groups shows: horizontal carousels (rails) or a grid per category.
enum LibraryLayout { rails, grid }

class SettingsController extends ChangeNotifier {
  SettingsController([this.api]);

  /// Optional API client. When present, the language preference is synced to the
  /// server so it follows the user across devices. Null in tests / pure-local use.
  final ApiClient? api;

  ThemeMode themeMode = ThemeMode.dark;
  List<String> languages = ['eng'];
  LibraryLayout libraryLayout = LibraryLayout.rails;

  /// True once a language preference has actually been chosen: loaded from storage,
  /// set by the user, or synced from the server. Until then (a fresh, logged-out
  /// app) the UI follows the DEVICE language, so public pages - login, the update
  /// gate - are translated even before we know the user.
  bool _explicit = false;

  // Content language (3-letter, as stored/synced) <-> UI locale (2-letter, as the
  // MaterialApp supports) for the languages we ship translations for.
  static const _contentToUi = {
    'eng': 'en', 'fra': 'fr', 'spa': 'es', 'deu': 'de', 'ita': 'it',
    'por': 'pt', 'jpn': 'ja', 'kor': 'ko', 'zho': 'zh',
  };
  static const _uiToContent = {
    'en': 'eng', 'fr': 'fra', 'es': 'spa', 'de': 'deu', 'it': 'ita',
    'pt': 'por', 'ja': 'jpn', 'ko': 'kor', 'zh': 'zho',
  };

  /// UI locale. With an explicit preference it's the primary content language;
  /// otherwise it follows the device language when we translate into it, else English.
  Locale? get locale {
    if (_explicit) {
      final ui = _contentToUi[languages.isEmpty ? 'eng' : languages.first];
      return ui == null ? null : Locale(ui);
    }
    return _deviceLocale();
  }

  Locale _deviceLocale() {
    for (final l in WidgetsBinding.instance.platformDispatcher.locales) {
      if (_uiToContent.containsKey(l.languageCode)) return Locale(l.languageCode);
    }
    return const Locale('en');
  }

  /// The device's primary language as a 3-letter content code, if we ship that
  /// translation; else null. Used to seed a new account's primary language at signup
  /// so the user reads everything in their language without touching settings.
  String? deviceContentLanguage() {
    for (final l in WidgetsBinding.instance.platformDispatcher.locales) {
      final code = _uiToContent[l.languageCode];
      if (code != null) return code;
    }
    return null;
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    themeMode = switch (prefs.getString('themeMode')) {
      'light' => ThemeMode.light,
      'system' => ThemeMode.system,
      _ => ThemeMode.dark,
    };
    final langs = prefs.getStringList('languages');
    if (langs != null && langs.isNotEmpty) {
      languages = langs;
      _explicit = true; // a stored preference exists -> stop following the device
    }
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
    _explicit = true;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('languages', languages);
    // Sync to the server so the choice follows the user across devices (best-effort;
    // the local cache stays the offline fallback).
    try {
      await api?.setLanguages(languages);
    } catch (_) {}
  }

  /// Adopt the server's languages (from `/api/me`) as the source of truth and cache
  /// them locally. Does NOT push back to the server, so it can't echo-loop.
  Future<void> hydrateFromServer(List<String> serverLangs) async {
    final langs = serverLangs.isEmpty ? ['eng'] : serverLangs;
    // Notify if the value changed OR if we're leaving the device-follow state, so
    // the locale flips from the device language to the account's preference.
    final changed = !_explicit || !listEquals(langs, languages);
    _explicit = true;
    languages = langs;
    if (changed) notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('languages', languages);
  }

  String get langsParam => languages.join(',');
}
