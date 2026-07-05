import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
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
                  // The backend reports the newest version (deployed in lockstep), so
                  // we build an exact link to it. Browser downloads it; the forced
                  // screen does the one-tap in-app install instead. Native apps probe
                  // the CPU for the small per-ABI split; web-on-Android gets the fat APK.
                  onPressed: () async {
                    final v = auth.serverVersion!;
                    final url = kIsWeb
                        ? Config.fatApkUrl(v)
                        : Config.apkUrl(v, abi: await deviceApkAbi());
                    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                  },
                  child: Text(t.update),
                ),
              IconButton(
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
