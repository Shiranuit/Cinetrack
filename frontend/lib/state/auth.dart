import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../config.dart';

class AuthController extends ChangeNotifier {
  /// Root navigator, so logout can clear any pushed screens (Settings/Profile).
  static final navigatorKey = GlobalKey<NavigatorState>();

  AuthController(this.api) {
    // A request that stays 401 even after a refresh attempt means the session is
    // dead — drop it so the app returns to the login screen.
    api.onUnauthorized = () {
      if (me != null) logout();
    };
  }

  final ApiClient api;
  Me? me;
  bool loading = true;

  /// Whether the backend allows self-registration (fetched at startup). Defaults to
  /// true so the UI stays usable if the flag can't be read; the login screen hides
  /// the "create an account" toggle when this is false.
  bool registrationEnabled = true;

  /// The backend's reported release, and whether THIS build is older than it (so the
  /// UI can prompt the user to update). Both set from `/api/config` at startup.
  String? serverVersion;
  bool updateAvailable = false;

  /// This build is below the server's MIN_APP_VERSION → the app is hard-blocked with
  /// a non-dismissible "update required" screen. Native only (web self-updates on
  /// reload), so we never dead-end a browser.
  bool updateRequired = false;

  bool get isAuthed => me != null;

  /// Restore a session on startup: try to mint an access token from the refresh
  /// token (web cookie / native secure storage). Succeeds silently or drops to login.
  Future<void> restore() async {
    // Feature flags + version check — best-effort; a failure just keeps the defaults.
    try {
      final cfg = await api.serverConfig();
      registrationEnabled = cfg.registrationEnabled;
      serverVersion = cfg.version;
      updateAvailable = isOlderVersion(Config.appVersion, cfg.version);
      // Force only across a breaking boundary (new major, or new minor while in 0.x);
      // patch/minor bumps are backward-compatible, so they only nudge via the banner.
      updateRequired = !kIsWeb && isBreakingBehind(Config.appVersion, cfg.minVersion);
    } catch (_) {}
    try {
      if (await api.tryRestore()) {
        me = await api.me();
      }
    } catch (_) {
      await api.clearLocalSession();
    }
    loading = false;
    notifyListeners();
  }

  Future<void> login(String email, String password) async {
    await api.login(email, password);
    me = await api.me();
    notifyListeners();
  }

  Future<void> register(String email, String password, String screenName, {String? inviteCode}) async {
    await api.register(email, password, screenName, inviteCode: inviteCode);
    me = await api.me();
    notifyListeners();
  }

  /// Re-fetch the current user (after profile edits like avatar/cover upload).
  Future<void> reloadMe() async {
    try {
      me = await api.me();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> logout() async {
    await api.logout();
    me = null;
    // Drop any pushed screens so we land cleanly on the login screen.
    navigatorKey.currentState?.popUntil((r) => r.isFirst);
    notifyListeners();
  }
}
