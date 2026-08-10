import 'dart:async';

import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../api/models.dart';
import '../design/app_colors.dart';
import '../design/tokens.dart';
import '../l10n/app_localizations.dart';
import 'confirm_actions.dart';
import 'filter_sheet.dart' show kLibrarySortKeys, kSortKeys, sortHelp, sortLabel;
import 'library_categories.dart';

/// A section's translated name in the customize sheet.
String sectionLabel(AppLocalizations t, LibrarySection s) {
  if (s.builtin == 'movies') return t.typeMovies;
  return builtinCats[s.builtin]?.title(t) ?? s.builtin;
}

/// Sorts a category may be ordered by. Mirrors `LIBRARY_SORTS` / `MOVIE_SORTS` in
/// `backend/src/tracking/mod.rs`.
///
/// Movies get the shorter list: they have no episodes, so "episodes left" and the
/// rest of the watch-history sorts would be settings that silently do nothing.
/// 'popularity' is in neither — the categorized view has no catalog score to order
/// by and would quietly fall back to last-watched.
List<String> sortsFor(String builtin) => builtin == 'movies'
    ? const ['my_rating', 'last_watched', 'name', 'year', 'runtime', 'updated']
    : [
        for (final k in kSortKeys)
          if (k != 'popularity') ...[k, if (k == 'rating') 'my_rating'],
        ...kLibrarySortKeys,
      ];

/// Persists a layout and returns it as stored (with server-assigned ids).
typedef LibrarySectionsSaver = Future<List<LibrarySection>> Function(List<LibrarySection>);

/// How long to wait after a change before persisting, so flicking several switches
/// or finishing a drag costs one request instead of one per gesture.
const _kAutoSaveDelay = Duration(milliseconds: 400);

/// Reorder / show / hide the Library's sections.
///
/// Saves itself, like the profile's customize sheet: every reorder and toggle
/// persists on its own (debounced), and [onSaved] reports the stored layout so the
/// Library behind the sheet can follow along. There is no Save button and no
/// confirmation step — closing the sheet, however it's closed, leaves nothing
/// unsaved.
class LibraryCustomizeSheet extends StatefulWidget {
  const LibraryCustomizeSheet({
    super.key,
    required this.sections,
    required this.save,
    this.onSaved,
  });
  final List<LibrarySection> sections;

  /// Injected rather than read from a provider so the auto-save behaviour is
  /// testable without a live client.
  final LibrarySectionsSaver save;

  /// Called with the stored layout after each successful save.
  final void Function(List<LibrarySection>)? onSaved;

  @override
  State<LibraryCustomizeSheet> createState() => LibraryCustomizeSheetState();
}

class LibraryCustomizeSheetState extends State<LibraryCustomizeSheet> {
  late final List<LibrarySection> _order = [...widget.sections];
  Timer? _debounce;
  bool _dirty = false; // edited since the last save STARTED
  bool _saving = false;
  String? _error;

  /// A built-in appears at most once, so its key is a stable list identity.
  Key _keyFor(LibrarySection s) => ValueKey(s.key);

  /// Record a change and schedule the save.
  void _touch() {
    _dirty = true;
    _debounce?.cancel();
    _debounce = Timer(_kAutoSaveDelay, _flush);
  }

  Future<void> _flush() async {
    _debounce?.cancel();
    if (!_dirty || _saving) return;
    _dirty = false;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await widget.save(List.of(_order));
      if (!mounted) return;
      setState(() {
        _saving = false;
        // Adopt the stored layout — it carries ids for sections the server just
        // created, so the next save updates them in place. Skipped when the user
        // edited again mid-flight, since `_order` is then newer than the response.
        if (!_dirty) {
          _order
            ..clear()
            ..addAll(saved);
        }
      });
      widget.onSaved?.call(saved);
      if (_dirty) _flush(); // a change landed during the request
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _dirty = true; // keep it pending so the next edit retries
        _error = e is ApiException ? e.message : '$e';
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    // Closing the sheet within the debounce window must not lose the change. The
    // widget is going away, so this can't await — it's fired off, and `onSaved`
    // still reaches the (still-mounted) Library screen.
    if (_dirty && !_saving) {
      widget.save(List.of(_order)).then((saved) => widget.onSaved?.call(saved)).catchError((_) => <LibrarySection>[]);
    }
    super.dispose();
  }

  /// Restore the stock layout: every category back in its default order and shown.
  ///
  /// Confirmed first: the sheet saves on its own, so there's no cancel to fall back
  /// on once this runs.
  Future<void> _resetLayout() async {
    final t = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.resetLayout),
        content: Text(t.resetLayoutConfirm),
        actions: confirmActions(
          ctx,
          confirmLabel: t.resetLayout,
          onConfirm: () => Navigator.of(ctx).pop(true),
          cancelLabel: t.cancel,
          onCancel: () => Navigator.of(ctx).pop(false),
          destructive: true,
        ),
      ),
    );
    if (ok != true || !mounted) return;

    // Reuse each built-in's existing row so its id survives the reset; the order,
    // the enabled flag and the sort all go back to stock.
    final existing = {for (final s in _order) s.builtin: s};
    setState(() => _order
      ..clear()
      ..addAll([
        for (final key in kBuiltinLibrarySections)
          (existing[key] ?? LibrarySection(builtin: key)).copyWith(
            enabled: true,
            sort: kSectionSortSeeds[key]?.$1,
            sortDesc: kSectionSortSeeds[key]?.$2,
          ),
      ]));
    _touch();
  }

  /// Pick the sort for one category.
  Future<void> _editSort(int index) async {
    final section = _order[index];
    final picked = await showModalBottomSheet<(String, bool)>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _SortPicker(
        title: sectionLabel(AppLocalizations.of(context), section),
        keys: sortsFor(section.builtin),
        sort: section.sort,
        desc: section.sortDesc,
      ),
    );
    if (picked == null || !mounted) return;
    if (picked.$1 == section.sort && picked.$2 == section.sortDesc) return;
    setState(() => _order[index] = section.copyWith(sort: picked.$1, sortDesc: picked.$2));
    _touch();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Insets.lg, 0, Insets.sm, Insets.sm),
            child: Row(
              children: [
                Expanded(child: Text(t.customizeLibrary, style: context.text.titleMedium)),
                // Changes persist on their own; this is just the reassurance that
                // something is happening, in place of a Save button.
                if (_saving)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                TextButton(
                  onPressed: _saving ? null : _resetLayout,
                  child: Text(t.resetLayout),
                ),
                const SizedBox(width: Insets.sm),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(Insets.lg, 0, Insets.lg, Insets.sm),
              child: Text(_error!, style: context.text.bodySmall?.copyWith(color: context.scheme.error)),
            ),
          const Divider(height: 1),
          Flexible(
            child: ReorderableListView(
              shrinkWrap: true,
              buildDefaultDragHandles: false,
              padding: const EdgeInsets.symmetric(vertical: Insets.sm),
              onReorderItem: (oldIndex, newIndex) {
                setState(() => _order.insert(newIndex, _order.removeAt(oldIndex)));
                _touch();
              },
              children: [
                for (var i = 0; i < _order.length; i++)
                  ListTile(
                    key: _keyFor(_order[i]),
                    leading: ReorderableDragStartListener(index: i, child: const Icon(Icons.drag_handle_rounded)),
                    title: Text(sectionLabel(t, _order[i])),
                    // What this category is ordered by when no sort is picked in
                    // the filter sheet. Tapping opens the picker — an inline
                    // dropdown per row would make a reorderable list unscannable.
                    subtitle: Text(
                      '${sortLabel(t, _order[i].sort)} ${_order[i].sortDesc ? '↓' : '↑'}',
                      style: context.text.labelSmall?.copyWith(color: context.scheme.onSurfaceVariant),
                    ),
                    onTap: _saving ? null : () => _editSort(i),
                    trailing: Switch(
                      value: _order[i].enabled,
                      onChanged: (on) {
                        setState(() => _order[i] = _order[i].copyWith(enabled: on));
                        _touch();
                      },
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Sort key + direction for one category, as a compact sheet: a dropdown and the
/// direction beside it, so the two read as the single choice they are.
class _SortPicker extends StatefulWidget {
  const _SortPicker({required this.title, required this.keys, required this.sort, required this.desc});
  final String title;
  final List<String> keys;
  final String sort;
  final bool desc;
  @override
  State<_SortPicker> createState() => _SortPickerState();
}

class _SortPickerState extends State<_SortPicker> {
  late String _sort = widget.keys.contains(widget.sort) ? widget.sort : widget.keys.first;
  late bool _desc = widget.desc;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            Insets.lg, 0, Insets.lg, MediaQuery.viewInsetsOf(context).bottom + Insets.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title, style: context.text.titleMedium),
            const SizedBox(height: Insets.xs),
            Text(t.categorySortHint,
                style: context.text.bodySmall?.copyWith(color: context.scheme.onSurfaceVariant)),
            const SizedBox(height: Insets.md),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _sort,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: Insets.lg, vertical: Insets.md),
                    ),
                    items: [
                      for (final key in widget.keys)
                        DropdownMenuItem(
                          value: key,
                          // "Episodes left" is a count and "Progress" a percentage;
                          // the labels alone don't say which is which.
                          child: Tooltip(
                            message: sortHelp(t, key),
                            child: Text(sortLabel(t, key), overflow: TextOverflow.ellipsis),
                          ),
                        ),
                    ],
                    onChanged: (k) => setState(() => _sort = k ?? _sort),
                  ),
                ),
                const SizedBox(width: Insets.sm),
                SegmentedButton<bool>(
                  showSelectedIcon: false,
                  style: const ButtonStyle(visualDensity: VisualDensity.compact),
                  segments: [
                    ButtonSegment(
                        value: true, icon: const Icon(Icons.arrow_downward_rounded), tooltip: t.sortDescending),
                    ButtonSegment(
                        value: false, icon: const Icon(Icons.arrow_upward_rounded), tooltip: t.sortAscending),
                  ],
                  selected: {_desc},
                  onSelectionChanged: (v) => setState(() => _desc = v.first),
                ),
              ],
            ),
            const SizedBox(height: Insets.md),
            // Full-width primary action as a direct Column child: the app themes
            // FilledButton with an infinite minimum width, so one inside a Row
            // would be asked to lay out at infinite width.
            FilledButton(
              onPressed: () => Navigator.of(context).pop((_sort, _desc)),
              child: Text(t.save),
            ),
          ],
        ),
      ),
    );
  }
}
