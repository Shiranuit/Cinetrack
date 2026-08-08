import 'dart:async';

import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../api/filters.dart';
import '../api/models.dart';
import '../design/app_colors.dart';
import '../design/tokens.dart';
import '../l10n/app_localizations.dart';
import 'filter_sheet.dart';
import 'library_categories.dart';

/// A section's name in the customize sheet: the translated label for a built-in,
/// the user's own title for a custom one.
String sectionLabel(AppLocalizations t, LibrarySection s) {
  if (s.isCustom) return s.title ?? '';
  if (s.builtin == 'movies') return t.typeMovies;
  return builtinCats[s.builtin]?.title(t) ?? s.builtin!;
}

/// Persists a layout and returns it as stored (with server-assigned ids).
typedef LibrarySectionsSaver = Future<List<LibrarySection>> Function(List<LibrarySection>);

/// How long to wait after a change before persisting, so flicking several switches
/// or finishing a drag costs one request instead of one per gesture.
const _kAutoSaveDelay = Duration(milliseconds: 400);

/// Reorder / toggle the Library's sections and manage custom ones.
///
/// Saves itself, like the profile's customize sheet: every reorder, toggle, add,
/// edit and delete persists on its own (debounced), and [onSaved] reports the
/// stored layout so the Library behind the sheet can follow along. There is no
/// Save button and no confirmation step — closing the sheet, however it's closed,
/// leaves nothing unsaved.
class LibraryCustomizeSheet extends StatefulWidget {
  const LibraryCustomizeSheet({
    super.key,
    required this.sections,
    required this.options,
    required this.save,
    this.onSaved,
  });
  final List<LibrarySection> sections;
  final FilterOptions options;

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

  /// New sections have no id yet, so they're keyed by identity until the server
  /// assigns one on save.
  Key _keyFor(LibrarySection s, int i) => ValueKey(s.key ?? 'new-$i-${identityHashCode(s)}');

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

  Future<void> _editCustom({LibrarySection? existing, int? index}) async {
    final edited = await showModalBottomSheet<LibrarySection>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => LibraryCategoryEditor(section: existing, options: widget.options),
    );
    if (edited == null || !mounted) return;
    setState(() => index == null ? _order.add(edited) : _order[index] = edited);
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
                    key: _keyFor(_order[i], i),
                    leading: ReorderableDragStartListener(index: i, child: const Icon(Icons.drag_handle_rounded)),
                    title: Text(sectionLabel(t, _order[i])),
                    // Custom sections are editable and removable; built-ins can only
                    // be reordered and hidden (they're computed, not configured).
                    subtitle: _order[i].isCustom ? Text(t.filters, style: context.text.labelSmall) : null,
                    onTap: _order[i].isCustom ? () => _editCustom(existing: _order[i], index: i) : null,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_order[i].isCustom)
                          IconButton(
                            tooltip: t.deleteCategory,
                            icon: const Icon(Icons.delete_outline_rounded),
                            onPressed: () {
                              setState(() => _order.removeAt(i));
                              _touch();
                            },
                          ),
                        Switch(
                          value: _order[i].enabled,
                          onChanged: (on) {
                            setState(() => _order[i] = _order[i].copyWith(enabled: on));
                            _touch();
                          },
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(Insets.sm),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: const Icon(Icons.add_rounded),
                label: Text(t.addCategory),
                onPressed: () => _editCustom(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Name + filter for one custom section. The filter itself is captured by the
/// existing [FilterSheet], so a saved category can express exactly what the
/// Library's own filter can.
class LibraryCategoryEditor extends StatefulWidget {
  const LibraryCategoryEditor({super.key, this.section, required this.options});
  final LibrarySection? section;
  final FilterOptions options;
  @override
  State<LibraryCategoryEditor> createState() => LibraryCategoryEditorState();
}

class LibraryCategoryEditorState extends State<LibraryCategoryEditor> {
  late final TextEditingController _name = TextEditingController(text: widget.section?.title ?? '');
  // Seeded from the saved filter when editing, so reopening a category shows the
  // facets it was built with rather than a blank sheet.
  late final AdvancedFilters _f = widget.section == null
      ? AdvancedFilters(defaultSort: 'my_rating')
      : AdvancedFilters.fromQuery(widget.section!.filters, defaultSort: 'my_rating');

  /// The kinds this category covers. Held separately from `_f.type` (a single
  /// value the filter sheet uses) and written back into the saved filter as a
  /// comma list on submit.
  late Set<String> _kinds = widget.section?.kinds.toSet() ?? {'series'};

  /// A segment label that shrinks instead of overflowing on a narrow sheet.
  static Widget _lbl(String s) => Text(s, maxLines: 1, softWrap: false, overflow: TextOverflow.fade);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _openFilters() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => FilterSheet(filters: _f, options: widget.options, showFavorites: true),
    );
    if (mounted) setState(() {}); // refresh the active-filter count
  }

  void _submit() {
    final title = _name.text.trim();
    if (title.isEmpty) return;
    // `id` carries over when editing so the server updates in place instead of
    // replacing the row (and the rail keeps its cached items).
    Navigator.of(context).pop(LibrarySection(
      id: widget.section?.id,
      title: title,
      // The kind chips own `type`, not the filter sheet's single-valued one.
      filters: {..._f.toQuery(), 'type': _kinds.join(',')},
      enabled: widget.section?.enabled ?? true,
    ));
  }

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
            Text(widget.section == null ? t.addCategory : t.editCategory, style: context.text.titleMedium),
            const SizedBox(height: Insets.md),
            TextField(
              controller: _name,
              autofocus: widget.section == null,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(labelText: t.categoryName),
              onChanged: (_) => setState(() {}), // enables/disables Save
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: Insets.md),
            // Which kinds the category covers. Multi-select, and it lives here
            // rather than in the filter sheet because it's part of what the
            // category IS — the Library's own toggles are a view on top.
            // `emptySelectionAllowed: false` keeps at least one kind, since a
            // category covering nothing can only ever render an empty rail.
            SegmentedButton<String>(
              multiSelectionEnabled: true,
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: [
                // Labels shrink rather than overflow on a narrow sheet.
                ButtonSegment(value: 'series', label: _lbl(t.typeSeries)),
                ButtonSegment(value: 'anime', label: _lbl(t.typeAnime)),
                ButtonSegment(value: 'movie', label: _lbl(t.typeMovies)),
              ],
              selected: _kinds,
              onSelectionChanged: (s) => setState(() {
                if (s.isNotEmpty) _kinds = s;
              }),
            ),
            const SizedBox(height: Insets.sm),
            Row(
              children: [
                Badge(
                  isLabelVisible: _f.activeCount > 0,
                  label: Text('${_f.activeCount}'),
                  child: TextButton.icon(
                    icon: const Icon(Icons.tune_rounded),
                    label: Text(t.filters),
                    onPressed: _openFilters,
                  ),
                ),
                const Spacer(),
                TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(t.cancel)),
              ],
            ),
            const SizedBox(height: Insets.sm),
            // Full-width primary action, as a direct Column child — the app themes
            // FilledButton with `Size.fromHeight(52)` (an INFINITE minimum width),
            // so one inside a Row would be asked to lay out at infinite width.
            FilledButton(
              onPressed: _name.text.trim().isEmpty ? null : _submit,
              child: Text(t.save),
            ),
          ],
        ),
      ),
    );
  }
}

