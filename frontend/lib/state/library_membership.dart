import 'package:flutter/foundation.dart';

import 'selection.dart';

/// A small client-side overlay of shows/movies added to the library during THIS
/// session, so cards (notably in Discover) can show the "In library" marker the
/// moment you follow / watch / favorite one, without a full reload that would
/// throw away the scroll position.
///
/// Additions only: the backend's `in_library` is monotonic for the actions you can
/// take from Discover. Following, watching an episode, favoriting, or setting a
/// status all upsert the tracking row, and unfollow / unwatch keep it (they only
/// flip flags), so a card never needs to LOSE the marker mid-session. [resolve]
/// therefore just ORs these local additions over the value the server returned when
/// the card's page was fetched. A real refresh reconciles everything from scratch.
class LibraryMembership extends ChangeNotifier {
  final Set<String> _added = {};

  static String _key(SelKind kind, int id) => '${kind.name}:$id';

  /// The effective "in library" for a card, layering local additions over the
  /// server value captured at page-fetch time.
  bool resolve(SelKind kind, int id, bool serverValue) =>
      serverValue || _added.contains(_key(kind, id));

  /// Record that this title is now in the library (idempotent).
  void add(SelKind kind, int id) {
    if (_added.add(_key(kind, id))) notifyListeners();
  }
}
