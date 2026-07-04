/// Compile-time configuration — everything here is baked in per build via
/// --dart-define, nothing is hardcoded to a specific deployment. Example:
///   flutter build web --release \
///     --dart-define=API_BASE=https://api.cine-track.com \
///     --dart-define=APP_VERSION=v1.0.0 \
///     --dart-define=GITHUB_REPO=Shiranuit/Cinetrack
class Config {
  /// Backend base URL.
  static const apiBase =
      String.fromEnvironment('API_BASE', defaultValue: 'http://localhost:8080');

  /// This build's release tag (e.g. "v1.0.0"), injected by CI from the git tag;
  /// "dev" for local/untagged builds.
  static const appVersion =
      String.fromEnvironment('APP_VERSION', defaultValue: 'dev');

  /// "owner/repo" used to resolve GitHub Release download links.
  static const githubRepo =
      String.fromEnvironment('GITHUB_REPO', defaultValue: 'Shiranuit/Cinetrack');

  /// A DIRECT link to the Android APK — the browser downloads it immediately, it
  /// does NOT open a GitHub page. For a tagged build it points at the APK for THIS
  /// exact release (so the web app hands out the version it is running); for an
  /// untagged/dev build it falls back to the stable-named asset on the latest
  /// release (`releases/latest/download/...` 302s straight to the newest APK).
  static String get androidApkUrl => appVersion.startsWith('v')
      ? 'https://github.com/$githubRepo/releases/download/$appVersion/cinetrack-$appVersion.apk'
      : 'https://github.com/$githubRepo/releases/latest/download/cinetrack.apk';
}

/// True if [current] is a strictly older release than [latest] (both "vX.Y.Z").
/// Returns false if either side isn't a parseable release tag (e.g. "dev"), so an
/// untagged/dev build never nags about updates and a malformed value is ignored.
bool isOlderVersion(String current, String? latest) {
  List<int>? parse(String? v) {
    if (v == null || !v.startsWith('v')) return null;
    final parts = v.substring(1).split('.');
    if (parts.length != 3) return null;
    final nums = [for (final p in parts) int.tryParse(p)];
    if (nums.any((n) => n == null)) return null;
    return nums.cast<int>();
  }

  final a = parse(current), b = parse(latest);
  if (a == null || b == null) return false;
  for (var i = 0; i < 3; i++) {
    if (a[i] != b[i]) return a[i] < b[i];
  }
  return false;
}
