import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../design/app_colors.dart';
import '../design/tokens.dart';
import '../l10n/app_localizations.dart';

/// True only in a browser on Android — the one case where offering the native
/// APK is useful. (On Flutter web, `defaultTargetPlatform` reflects the browser.)
bool get isWebOnAndroid => kIsWeb && defaultTargetPlatform == TargetPlatform.android;

// Dismissed for the rest of the session (kept deliberately simple; reappears on reload).
bool _dismissed = false;

/// A slim, dismissible top banner shown to web-on-Android visitors, offering the
/// APK that matches this exact web release. Renders nothing everywhere else, so
/// it is safe to mount unconditionally above the whole app.
class AndroidInstallBanner extends StatefulWidget {
  const AndroidInstallBanner({super.key});
  @override
  State<AndroidInstallBanner> createState() => _AndroidInstallBannerState();
}

class _AndroidInstallBannerState extends State<AndroidInstallBanner> {
  @override
  Widget build(BuildContext context) {
    if (!isWebOnAndroid || _dismissed) return const SizedBox.shrink();
    final t = AppLocalizations.of(context);
    return Material(
      color: context.scheme.primaryContainer,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Insets.lg, Insets.xs, Insets.xs, Insets.xs),
          child: Row(
            children: [
              Icon(Icons.android_rounded, size: 20, color: context.scheme.onPrimaryContainer),
              const SizedBox(width: Insets.sm),
              Expanded(
                child: Text(t.installAndroidBanner,
                    style: context.text.bodyMedium?.copyWith(color: context.scheme.onPrimaryContainer)),
              ),
              TextButton(
                // Web can't probe the visitor's CPU, so hand out the fat (all-ABIs)
                // APK that installs on any device — pinned to the version this web
                // build is (equals the latest release, since they deploy in lockstep).
                onPressed: () =>
                    launchUrl(Uri.parse(Config.fatApkUrl(Config.appVersion)), mode: LaunchMode.externalApplication),
                child: Text(t.installAndroidCta),
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
