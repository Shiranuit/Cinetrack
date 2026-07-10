import 'package:flutter/material.dart';

import '../design/tokens.dart';

/// Consistent confirm/cancel actions for [AlertDialog]s across the app: the
/// committing [confirmLabel] action is OUTLINED (red when [destructive]) on the
/// left, and the safe [cancelLabel] is FILLED and prominent on the right — equal
/// width, side by side. This makes the non-committal choice the obvious one and
/// the action a deliberate tap. Pass `onConfirm: null` to keep the action disabled
/// (e.g. until a field validates).
///
/// Returned as a single full-width row so it survives the app's full-width button
/// theme (a plain `actions:` list would stretch each button and stack them). Labels
/// wrap to two lines when a (localized) label is long, and [IntrinsicHeight] keeps
/// both buttons the same height. Drop straight into `AlertDialog.actions`.
List<Widget> confirmActions(
  BuildContext context, {
  required String confirmLabel,
  required VoidCallback? onConfirm,
  required String cancelLabel,
  required VoidCallback onCancel,
  bool destructive = false,
}) {
  final scheme = Theme.of(context).colorScheme;
  const shape = RoundedRectangleBorder(borderRadius: Radii.card);
  return [
    IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: onConfirm,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                shape: shape,
                foregroundColor: destructive ? scheme.error : null,
                side: destructive ? BorderSide(color: scheme.error) : null,
              ),
              child: Text(confirmLabel, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
          ),
          const SizedBox(width: Insets.sm),
          Expanded(
            child: FilledButton(
              onPressed: onCancel,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48), shape: shape),
              child: Text(cancelLabel, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
          ),
        ],
      ),
    ),
  ];
}
