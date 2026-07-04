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

  /// The Android APK matching THIS exact release (so the web app hands out the
  /// same version it is), or the latest-release page for untagged/dev builds.
  static String get androidApkUrl => appVersion.startsWith('v')
      ? 'https://github.com/$githubRepo/releases/download/$appVersion/cinetrack-$appVersion.apk'
      : 'https://github.com/$githubRepo/releases/latest';
}
