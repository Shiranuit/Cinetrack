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

  /// Always the NEWEST published APK, version-independent. Used by the in-app updater
  /// — an outdated build must NOT re-download its own (`androidApkUrl`) version.
  static String get latestApkUrl =>
      'https://github.com/$githubRepo/releases/latest/download/cinetrack.apk';
}

/// Parses a "MAJOR.MINOR.PATCH" release tag into `[major, minor, patch]`. The leading
/// "v" is optional (git tags carry it, a hand-set env var might not), so both
/// "v0.2.4" and "0.2.4" work. Returns null for anything that isn't three numeric
/// parts (e.g. "dev", "v1.0", "v0.2.4-rc1") so callers safely ignore it.
List<int>? _parseVersion(String? v) {
  if (v == null) return null;
  var s = v.trim();
  if (s.startsWith('v') || s.startsWith('V')) s = s.substring(1);
  final parts = s.split('.');
  if (parts.length != 3) return null;
  final nums = [for (final p in parts) int.tryParse(p)];
  if (nums.any((n) => n == null)) return null;
  return nums.cast<int>();
}

/// True if [current] is a strictly older release than [latest] (any segment).
/// Drives the OPTIONAL "a new version is available" prompt. Returns false if either
/// side isn't a parseable release tag (e.g. "dev"), so dev builds never nag.
bool isOlderVersion(String current, String? latest) {
  final a = _parseVersion(current), b = _parseVersion(latest);
  if (a == null || b == null) return false;
  for (var i = 0; i < 3; i++) {
    if (a[i] != b[i]) return a[i] < b[i];
  }
  return false;
}

/// True only if [current] is behind [floor] across a BREAKING boundary — a change
/// that can make an old client incompatible, so it must be force-updated. Follows
/// semver: the major version is the breaking segment once >= 1.0.0; while still in
/// 0.x, every minor is treated as breaking (0.x makes no stability promise). Patch
/// bumps (and minor bumps within a >= 1.0 major) never force. Non-tags return false.
bool isBreakingBehind(String current, String? floor) {
  final c = _parseVersion(current), f = _parseVersion(floor);
  if (c == null || f == null) return false;
  if (c[0] != f[0]) return c[0] < f[0]; // different major -> breaking
  if (f[0] == 0 && c[1] != f[1]) return c[1] < f[1]; // within 0.x, minor is breaking
  return false;
}
