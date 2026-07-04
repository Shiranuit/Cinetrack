import 'dart:io';

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../config.dart';

/// The in-app APK updater only makes sense on a native Android build (a sideloaded
/// app that can install another APK). iOS has no public build; web self-updates.
bool get canInstallApk => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// Download the LATEST published APK and hand it to the system package installer.
/// [onProgress] receives 0..1, or null when the size is unknown. Throws on failure.
///
/// Not a silent install: Android shows its own install confirmation, and the first
/// time it prompts the user to allow this app to "install unknown apps".
Future<void> downloadAndInstallLatestApk({void Function(double?)? onProgress}) async {
  final client = http.Client();
  try {
    final resp = await client.send(http.Request('GET', Uri.parse(Config.latestApkUrl)));
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
