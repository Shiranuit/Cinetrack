import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../design/app_colors.dart';
import '../design/tokens.dart';
import '../l10n/app_localizations.dart';
import '../services/apk_updater.dart';
import '../state/auth.dart';

/// Full-screen, NON-DISMISSIBLE block shown when this build is older than the
/// backend's MIN_APP_VERSION. The only way forward is to install the new version:
/// the button downloads the latest APK and launches the system installer.
class UpdateRequiredScreen extends StatefulWidget {
  const UpdateRequiredScreen({super.key});
  @override
  State<UpdateRequiredScreen> createState() => _UpdateRequiredScreenState();
}

class _UpdateRequiredScreenState extends State<UpdateRequiredScreen> {
  bool _busy = false;
  double? _progress; // 0..1 while downloading; null = indeterminate
  String? _error;

  Future<void> _update() async {
    // The newest version to install, as reported by the backend over /api/config
    // (deployed in lockstep with releases, so it's always the latest).
    final version = context.read<AuthController>().serverVersion;
    if (version == null) {
      setState(() => _error = AppLocalizations.of(context).updateFailed);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _progress = null;
    });
    try {
      await downloadAndInstallApk(
        version,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      // The OS installer is now in front; leave the button in a busy state.
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = AppLocalizations.of(context).updateFailed;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return PopScope(
      canPop: false, // block the Android back button — the gate can't be dismissed.
      child: Scaffold(
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Insets.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.system_update_rounded, size: 64, color: context.scheme.primary),
                  const SizedBox(height: Insets.lg),
                  Text(t.updateRequired,
                      textAlign: TextAlign.center, style: context.text.headlineSmall),
                  const SizedBox(height: Insets.sm),
                  Text(t.updateRequiredBody,
                      textAlign: TextAlign.center,
                      style: context.text.bodyMedium?.copyWith(color: context.scheme.onSurfaceVariant)),
                  if (_error != null) ...[
                    const SizedBox(height: Insets.md),
                    Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: context.scheme.error)),
                  ],
                  const SizedBox(height: Insets.xl),
                  if (canInstallApk)
                    FilledButton.icon(
                      onPressed: _busy ? null : _update,
                      icon: _busy
                          ? SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, value: _progress),
                            )
                          : const Icon(Icons.download_rounded),
                      label: Text(_busy && _progress != null
                          ? '${(_progress! * 100).round()}%'
                          : t.update),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
