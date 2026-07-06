import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';

/// The in-app APK updater only makes sense on a native Android build (a sideloaded
/// app that can install another APK). iOS has no public build; web self-updates.
bool get canInstallApk => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

String? _cachedAbi;

/// The best ABI for THIS device among the split APKs we publish, cached for the
/// session. `supportedAbis` is ordered by device preference (arm64 first on a
/// 64-bit phone), so the first match is the smallest APK it can run. Falls back to
/// [Config.defaultApkAbi] off native Android or if the probe fails.
Future<String> deviceApkAbi() async {
  if (_cachedAbi != null) return _cachedAbi!;
  var abi = Config.defaultApkAbi;
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      abi = info.supportedAbis.firstWhere(
        Config.apkAbis.contains,
        orElse: () => Config.defaultApkAbi,
      );
    } catch (_) {
      // Keep the default; a bad probe must never block the update.
    }
  }
  return _cachedAbi = abi;
}

/// Download the APK for [version] (the newest release, as reported by the backend
/// over /api/config) and hand it to the system package installer. [onProgress]
/// receives 0..1, or null when the size is unknown. Throws on failure.
///
/// Not a silent install: Android shows its own install confirmation, and the first
/// time it prompts the user to allow this app to "install unknown apps".
Future<void> downloadAndInstallApk(String version, {void Function(double?)? onProgress}) async {
  final client = http.Client();
  try {
    final abi = await deviceApkAbi();
    final resp = await client.send(http.Request('GET', Uri.parse(Config.apkUrl(version, abi: abi))));
    if (resp.statusCode != 200) {
      throw Exception('download failed (HTTP ${resp.statusCode})');
    }
    final total = resp.contentLength ?? 0;
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/cinetrack-update.apk');
    final sink = file.openWrite();
    var received = 0;
    await for (final chunk in resp.stream) {
      sink.add(chunk);
      received += chunk.length;
      onProgress?.call(total > 0 ? received / total : null);
    }
    await sink.close();

    // Opening an .apk launches the system package installer.
    final result = await OpenFilex.open(
      file.path,
      type: 'application/vnd.android.package-archive',
    );
    if (result.type != ResultType.done) {
      throw Exception('could not open the installer: ${result.message}');
    }
  } finally {
    client.close();
  }
}

/// Manual-install fallback: open the browser to download the fat (all-ABI) APK for
/// [version]. Used when the in-app installer can't run - the user declined the
/// "install unknown apps" permission, the system installer failed to launch, or
/// we're on web-on-Android where an in-app install isn't possible. The fat APK is
/// used so the downloaded file installs regardless of the device's ABI.
Future<void> downloadApkInBrowser(String version) =>
    launchUrl(Uri.parse(Config.fatApkUrl(version)), mode: LaunchMode.externalApplication);
