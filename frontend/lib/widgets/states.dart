import 'package:flutter/material.dart';

import '../design/app_colors.dart';
import '../design/tokens.dart';
import '../l10n/app_localizations.dart';

class LoadingView extends StatelessWidget {
  const LoadingView({super.key});
  @override
  Widget build(BuildContext context) => const Center(child: CircularProgressIndicator());
}

class MessageView extends StatelessWidget {
  const MessageView({super.key, required this.icon, required this.message, this.action});
  final IconData icon;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Insets.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: context.scheme.onSurfaceVariant),
            const SizedBox(height: Insets.md),
            Text(message, textAlign: TextAlign.center, style: context.text.bodyMedium?.copyWith(color: context.scheme.onSurfaceVariant)),
            if (action != null) ...[const SizedBox(height: Insets.lg), action!],
          ],
        ),
      ),
    );
  }
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => MessageView(
        icon: Icons.cloud_off_rounded,
        message: message,
        action: FilledButton.tonal(onPressed: onRetry, child: Text(AppLocalizations.of(context).retry)),
      );
}
