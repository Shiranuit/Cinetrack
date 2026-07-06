import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../design/app_colors.dart';
import '../design/tokens.dart';
import '../l10n/app_localizations.dart';
import '../services/apk_updater.dart';
import '../state/auth.dart';

/// On Android (native app, or a browser on Android) we can offer a one-tap APK
/// download. iOS has no public build; a web app just needs a reload.
bool get _isAndroid => defaultTargetPlatform == TargetPlatform.android;

// Dismissed for the rest of the session (kept simple; reappears on next launch
// until the user updates, at which point the versions match and it stops showing).
bool _dismissed = false;

/// A slim, dismissible banner shown when THIS build is older than the backend
/// (see [AuthController.updateAvailable], set from `/api/config` at startup).
/// Renders nothing otherwise, so it's safe to mount unconditionally above the app.
class UpdateBanner extends StatefulWidget {
  const UpdateBanner({super.key});
  @override
  State<UpdateBanner> createState() => _UpdateBannerState();
}

class _UpdateBannerState extends State<UpdateBanner> {
  bool _busy = false;
  double? _progress; // 0..1 while downloading; null = indeterminate

  /// Same behaviour as the forced-update screen: on a native Android build,
  /// download the matching APK and hand it to the system installer (one tap,
  /// no manual "open the download" step). On web-on-Android we can't install
  /// in-app, so we fall back to letting the browser download the fat APK.
  Future<void> _update(String version) async {
    final messenger = ScaffoldMessenger.of(context);
    final t = AppLocalizations.of(context);
    // web-on-Android can't install in-app: just download the APK in the browser.
    if (!canInstallApk) {
      await downloadApkInBrowser(version);
      return;
    }
    // Check the "install unknown apps" permission up front (prompting for it if
    // needed). If it's not granted, don't bother with the in-app installer - which
    // would hand off and silently do nothing - and download for a manual install.
    if (!await ensureInstallPermission()) {
      if (!mounted) return;
      await downloadApkInBrowser(version);
      messenger.showSnackBar(SnackBar(content: Text(t.updateOpenToInstall)));
      return;
    }
    setState(() {
      _busy = true;
      _progress = null;
    });
    try {
      await downloadAndInstallApk(
        version,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      // The OS installer is now in front; leave the button busy.
    } catch (_) {
      // Couldn't install in-app (e.g. the "install unknown apps" permission was
      // declined). Fall back to a browser download so the user can install it by
      // hand from their Downloads.
      if (mounted) {
        setState(() => _busy = false);
        await downloadApkInBrowser(version);
        messenger.showSnackBar(SnackBar(content: Text(t.updateOpenToInstall)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    // Show the slim nudge only for a NON-breaking update. When an update is forced,
    // the full-screen "Update required" gate already covers it, so hide the banner.
    if (!auth.updateAvailable || auth.updateRequired || _dismissed) {
      return const SizedBox.shrink();
    }
    final t = AppLocalizations.of(context);
    return Material(
      color: context.scheme.tertiaryContainer,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Insets.lg, Insets.xs, Insets.xs, Insets.xs),
          child: Row(
            children: [
              Icon(Icons.system_update_rounded, size: 20, color: context.scheme.onTertiaryContainer),
              const SizedBox(width: Insets.sm),
              Expanded(
                child: Text(t.updateAvailable,
                    style: context.text.bodyMedium?.copyWith(color: context.scheme.onTertiaryContainer)),
              ),
              if (_isAndroid && auth.serverVersion != null)
                TextButton(
                  onPressed: _busy ? null : () => _update(auth.serverVersion!),
                  child: _busy
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, value: _progress),
                            ),
                            if (_progress != null) ...[
                              const SizedBox(width: 6),
                              Text('${(_progress! * 100).round()}%'),
                            ],
                          ],
                        )
                      : Text(t.update),
                ),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: _busy ? null : () => setState(() => _dismissed = true),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
