import 'package:flutter/material.dart';

import '../design/app_colors.dart';
import '../l10n/app_localizations.dart';

/// Presentation for the Library's built-in categories, shared by the Library
/// screen and the customize sheet.
typedef AccentFn = Color Function(BuildContext);

class LibCat {
  const LibCat(this.title, this.icon, this.accent);
  final String Function(AppLocalizations) title;
  final IconData icon;
  final AccentFn accent;
}

/// Presentation for each built-in category, keyed by the section key the server
/// stores (`kBuiltinLibrarySections`). 'movies' is rendered from the movie list
/// rather than a `Library` bucket, so it has no entry here.
final builtinCats = <String, LibCat>{
  'watching': LibCat((t) => t.catWatching, Icons.play_circle_rounded, (c) => c.scheme.primary),
  'up_to_date': LibCat((t) => t.catUpToDate, Icons.check_circle_rounded, (c) => c.colors.seen),
  'stale': LibCat((t) => t.catStale, Icons.history_rounded, (c) => c.colors.warning),
  'not_started': LibCat((t) => t.catNotStarted, Icons.playlist_add_rounded, (c) => c.scheme.secondary),
  'stopped': LibCat((t) => t.catStopped, Icons.pause_circle_rounded, (c) => c.scheme.onSurfaceVariant),
  'for_later': LibCat((t) => t.watchLater, Icons.schedule_rounded, (c) => c.scheme.tertiary),
};

