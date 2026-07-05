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

  /// The Android ABIs we publish a SEPARATE (split-per-abi) APK for, in DESCENDING
  /// preference order. Each is ~a third the size of the fat multi-ABI build, so a
  /// device downloads only the native code it can actually run. arm64 comes first
  /// because it fits effectively every phone since ~2017.
  static const apkAbis = ['arm64-v8a', 'armeabi-v7a', 'x86_64'];

  /// ABI assumed when the running platform can't be probed for its CPU. Only reached
  /// on native Android if detection fails; the web path uses the fat APK instead.
  static const defaultApkAbi = 'arm64-v8a';

  /// Direct link to the per-ABI split APK for [version] (a git tag like "v0.5.0").
  /// The backend is deployed in lockstep with releases, so the version it reports
  /// over /api/config is always the newest one — the updater builds an exact link
  /// from it and we never publish (or need) a floating "latest" alias.
  static String apkUrl(String version, {String abi = defaultApkAbi}) =>
      'https://github.com/$githubRepo/releases/download/$version/cinetrack-$version-$abi.apk';

  /// Direct link to the FAT (all-ABIs) APK for [version] — used by the web install
  /// button, where the visitor's phone CPU can't be probed, so it installs on any
  /// device. The browser downloads it immediately; it does NOT open a GitHub page.
  static String fatApkUrl(String version) =>
      'https://github.com/$githubRepo/releases/download/$version/cinetrack-$version.apk';
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
