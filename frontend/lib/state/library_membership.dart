import 'package:flutter/foundation.dart';

import 'selection.dart';

/// A small client-side overlay of library membership changes made during THIS
/// session, so cards (notably in Discover) reflect an add/remove the moment you
/// act, without a full reload that would throw away the scroll position.
///
/// Membership is NOT monotonic: unfollowing a show (with no favorite/status) drops
/// it from the library, so the marker must be able to disappear too. [resolve]
/// therefore layers both local [add]s and [remove]s over the value the server
/// returned when the card's page was fetched: a removal forces "not in library"
/// even if the captured server value was still true. A real refresh reconciles
/// everything from scratch.
class LibraryMembership extends ChangeNotifier {
  final Set<String> _added = {};
  final Set<String> _removed = {};

  static String _key(SelKind kind, int id) => '${kind.name}:$id';

  /// The effective "in library" for a card, layering local changes over the server
  /// value captured at page-fetch time (a local removal wins over a stale `true`).
  bool resolve(SelKind kind, int id, bool serverValue) {
    final k = _key(kind, id);
    if (_removed.contains(k)) return false;
    return serverValue || _added.contains(k);
  }

  /// Record that this title is now in the library (idempotent).
  void add(SelKind kind, int id) {
    final k = _key(kind, id);
    final changed = _removed.remove(k) | _added.add(k);
    if (changed) notifyListeners();
  }

  /// Record that this title is no longer in the library (idempotent).
  void remove(SelKind kind, int id) {
    final k = _key(kind, id);
    final changed = _added.remove(k) | _removed.add(k);
    if (changed) notifyListeners();
  }
}
