import 'dart:async';

import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../api/models.dart';
import '../design/app_colors.dart';
import '../design/tokens.dart';
import '../l10n/app_localizations.dart';
import 'confirm_actions.dart';
import 'library_categories.dart';

/// A section's translated name in the customize sheet.
String sectionLabel(AppLocalizations t, LibrarySection s) {
  if (s.builtin == 'movies') return t.typeMovies;
  return builtinCats[s.builtin]?.title(t) ?? s.builtin;
}

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

    // Reuse each built-in's existing row so its id survives the reset; only the
    // order and the enabled flag are being restored.
    final existing = {for (final s in _order) s.builtin: s};
    setState(() => _order
      ..clear()
      ..addAll([
        for (final key in kBuiltinLibrarySections)
          (existing[key] ?? LibrarySection(builtin: key)).copyWith(enabled: true),
      ]));
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
