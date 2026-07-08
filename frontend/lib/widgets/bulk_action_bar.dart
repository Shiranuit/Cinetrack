import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../design/app_colors.dart';
import '../design/tokens.dart';
import '../l10n/app_localizations.dart';
import '../state/library_membership.dart';
import '../state/selection.dart';

/// Bottom bar of bulk actions, shown while [controller] has a non-empty selection.
/// Each action runs over the selected items (applying only where it makes sense:
/// follow / for-later / stop are series-only, watch & favorite cover both), then
/// clears the selection and calls [onChanged] so the screen refreshes.
class BulkActionBar extends StatefulWidget {
  const BulkActionBar({
    super.key,
    required this.controller,
    this.onChanged,
    this.inLibrary = false,
  });
  final SelectionController controller;
  final Future<void> Function()? onChanged;

  /// In the Library everything is already followed, so the follow slot becomes
  /// "Unfollow" (drop from the library). In Discover it's "Follow" (add).
  final bool inLibrary;

  @override
  State<BulkActionBar> createState() => _BulkActionBarState();
}

class _BulkActionBarState extends State<BulkActionBar> {
  bool _busy = false;

  /// Run `op` over the selected items that `applies`, a few at a time so a big
  /// selection doesn't fire dozens of simultaneous requests. Returns how many ran.
  Future<int> _run(
    List<SelItem> items,
    Future<void> Function(ApiClient, SelItem) op,
  ) async {
    final api = context.read<ApiClient>();
    const chunk = 4;
    var done = 0;
    for (var i = 0; i < items.length; i += chunk) {
      final batch = items.skip(i).take(chunk);
      final results = await Future.wait(
        batch.map((it) async {
          try {
            await op(api, it);
            return true;
          } catch (_) {
            return false;
          }
        }),
      );
      done += results.where((ok) => ok).length;
    }
    return done;
  }

  Future<void> _act(
    bool Function(SelItem) applies,
    Future<void> Function(ApiClient, SelItem) op,
  ) async {
    if (_busy) return;
    final t = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final membership = context.read<LibraryMembership>();
    final items = widget.controller.items.where(applies).toList();
    setState(() => _busy = true);
    try {
      final n = await _run(items, op);
      // Every bulk action here creates the tracking row (follow / watch / status /
      // favorite), so mark the acted items in library right away — Discover cards
      // pick up the pill + border without a reload.
      for (final it in items) {
        membership.add(it.kind, it.id);
      }
      widget.controller.clear();
      messenger.showSnackBar(SnackBar(content: Text(t.bulkUpdated(n))));
      if (widget.onChanged != null) await widget.onChanged!();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool _isSeries(SelItem it) => it.kind == SelKind.series;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Material(
      elevation: 8,
      color: context.scheme.surfaceContainerHigh,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 60,
          child: Row(
            children: [
              IconButton(
                tooltip: t.clear,
                icon: const Icon(Icons.close_rounded),
                onPressed: _busy ? null : widget.controller.clear,
              ),
              Text(
                t.nSelected(widget.controller.count),
                style: context.text.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: Insets.sm),
              if (_busy)
                const Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: EdgeInsets.only(right: Insets.md),
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
                )
              else
                // Right-aligned, and horizontally scrollable so five actions never
                // overflow on a narrow phone.
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    reverse: true,
                    child: Row(
                      children: [
                        _action(
                          t.markAllWatched,
                          Icons.done_all_rounded,
                          () => _act(
                            (_) => true,
                            (api, it) => it.kind == SelKind.series
                                ? api.watchSeries(it.id)
                                : api.watchMovie(it.id),
                          ),
                        ),
                        if (widget.inLibrary)
                          _action(
                            t.unfollow,
                            Icons.remove_circle_outline_rounded,
                            () => _act(
                              _isSeries,
                              (api, it) => api.setFollow(it.id, false),
                            ),
                          )
                        else
                          _action(
                            t.follow,
                            Icons.add_rounded,
                            () => _act(
                              _isSeries,
                              (api, it) => api.setFollow(it.id, true),
                            ),
                          ),
                        _action(
                          t.watchLater,
                          Icons.schedule_rounded,
                          () => _act(
                            (_) => true,
                            (api, it) => it.kind == SelKind.series
                                ? api.setStatus(it.id, 'for_later')
                                : api.watchlistMovie(it.id, true),
                          ),
                        ),
                        _action(
                          t.addToFavorites,
                          Icons.favorite_rounded,
                          () => _act(
                            (_) => true,
                            (api, it) => it.kind == SelKind.series
                                ? api.setFavorite(it.id, true)
                                : api.favoriteMovie(it.id, true),
                          ),
                        ),
                        _action(
                          t.stopWatching,
                          Icons.pause_circle_rounded,
                          () => _act(
                            _isSeries,
                            (api, it) => api.setStatus(it.id, 'stopped'),
                          ),
                        ),
                        const SizedBox(width: Insets.xs),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _action(String tooltip, IconData icon, VoidCallback onPressed) =>
      IconButton(tooltip: tooltip, icon: Icon(icon), onPressed: onPressed);
}
