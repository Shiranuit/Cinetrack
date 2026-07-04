import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../design/app_colors.dart';
import '../design/tokens.dart';
import '../l10n/app_localizations.dart';
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
              if (_isAndroid)
                TextButton(
                  // Latest (not this build's own version); browser downloads it, the
                  // forced-update screen does the one-tap in-app install instead.
                  onPressed: () =>
                      launchUrl(Uri.parse(Config.latestApkUrl), mode: LaunchMode.externalApplication),
                  child: Text(t.update),
                ),
              IconButton(
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: () => setState(() => _dismissed = true),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
