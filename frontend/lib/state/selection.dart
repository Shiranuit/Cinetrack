import 'package:flutter/widgets.dart';

/// What a selected card points at — a series (includes anime) or a movie. Bulk
/// actions branch on this because a movie has no follow/status, only watch/favorite.
enum SelKind { series, movie }

@immutable
class SelItem {
  const SelItem(this.kind, this.id, this.name);
  final SelKind kind;
  final int id;
  final String name;

  /// Stable key across the two id spaces (a series id and a movie id can collide).
  String get key => '${kind.name}:$id';
}

/// A multi-select over show/movie cards, driving the bulk-action bar. A screen owns
/// one and exposes it through a [SelectionScope]; cards toggle membership and read
/// it to render their checkbox. Empty selection == not in selection mode.
class SelectionController extends ChangeNotifier {
  final Map<String, SelItem> _items = {};

  bool get active => _items.isNotEmpty;
  int get count => _items.length;
  List<SelItem> get items => _items.values.toList(growable: false);
  bool contains(SelKind kind, int id) => _items.containsKey('${kind.name}:$id');

  /// Add without toggling off — used by long-press to enter selection mode.
  void select(SelItem it) {
    if (_items.containsKey(it.key)) return;
    _items[it.key] = it;
    notifyListeners();
  }

  void toggle(SelItem it) {
    if (_items.remove(it.key) == null) _items[it.key] = it;
    notifyListeners();
  }

  void clear() {
    if (_items.isEmpty) return;
    _items.clear();
    notifyListeners();
  }
}

/// Provides a [SelectionController] to the cards below it. Cards call
/// [SelectionScope.of] (listening, so they rebuild on selection change) to render
/// their state, and [SelectionScope.read] (non-listening) from gesture callbacks.
class SelectionScope extends InheritedNotifier<SelectionController> {
  const SelectionScope({super.key, required SelectionController controller, required super.child})
      : super(notifier: controller);

  static SelectionController? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SelectionScope>()?.notifier;

  static SelectionController? read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<SelectionScope>()?.notifier;
}
