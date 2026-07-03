import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../design/app_colors.dart';
import '../design/tokens.dart';

/// Long-press context menu for a show: quick favorite / status / remove actions.
Future<void> showShowContextSheet(
  BuildContext context, {
  required int seriesId,
  required String title,
  Future<void> Function()? onChanged,
}) {
  final api = context.read<ApiClient>();
  final messenger = ScaffoldMessenger.of(context);

  Future<void> run(BuildContext sheetCtx, String label, Future<void> Function() action) async {
    Navigator.pop(sheetCtx);
    try {
      await action();
      messenger.showSnackBar(SnackBar(content: Text(label)));
      if (onChanged != null) await onChanged();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  return showModalBottomSheet(
    context: context,
    showDragHandle: true,
    builder: (sheetCtx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Insets.lg, 0, Insets.lg, Insets.sm),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(title, style: sheetCtx.text.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: Icon(Icons.favorite_rounded, color: sheetCtx.colors.favorite),
            title: const Text('Add to favorites'),
            onTap: () => run(sheetCtx, 'Added to favorites', () => api.setFavorite(seriesId, true)),
          ),
          ListTile(
            leading: const Icon(Icons.schedule_rounded),
            title: const Text('Watch later'),
            onTap: () => run(sheetCtx, 'Marked for later', () => api.setStatus(seriesId, 'for_later')),
          ),
          ListTile(
            leading: const Icon(Icons.pause_circle_rounded),
            title: const Text('Stop watching'),
            onTap: () => run(sheetCtx, 'Stopped watching', () => api.setStatus(seriesId, 'stopped')),
          ),
          ListTile(
            leading: Icon(Icons.delete_outline_rounded, color: sheetCtx.scheme.error),
            title: Text('Remove from library', style: TextStyle(color: sheetCtx.scheme.error)),
            onTap: () => run(sheetCtx, 'Removed', () => api.removeShow(seriesId)),
          ),
          const SizedBox(height: Insets.sm),
        ],
      ),
    ),
  );
}
