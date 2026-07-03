import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import '../api/models.dart';

class AuthController extends ChangeNotifier {
  /// Root navigator, so logout can clear any pushed screens (Settings/Profile).
  static final navigatorKey = GlobalKey<NavigatorState>();

  AuthController(this.api) {
    // Any authenticated request coming back 401 (deleted account / expired token)
    // drops the session so the app returns to the login screen.
    api.onUnauthorized = () {
      if (me != null) logout();
    };
  }

  final ApiClient api;
  Me? me;
  bool loading = true;

  bool get isAuthed => me != null;

  /// Restore a saved token on startup and validate it.
  Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token != null) {
      api.token = token;
      try {
        me = await api.me();
      } catch (_) {
        api.token = null;
        await prefs.remove('token');
      }
    }
    loading = false;
    notifyListeners();
  }

  Future<void> _persist(String token) async {
    api.token = token;
    (await SharedPreferences.getInstance()).setString('token', token);
    me = await api.me();
    notifyListeners();
  }

  Future<void> login(String email, String password) async {
    final (token, _) = await api.login(email, password);
    await _persist(token);
  }

  Future<void> register(String email, String password, String screenName) async {
    final (token, _) = await api.register(email, password, screenName);
    await _persist(token);
  }

  /// Re-fetch the current user (after profile edits like avatar/cover upload).
  Future<void> reloadMe() async {
    try {
      me = await api.me();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> logout() async {
    api.token = null;
    me = null;
    // Drop any pushed screens so we land cleanly on the login screen.
    navigatorKey.currentState?.popUntil((r) => r.isFirst);
    (await SharedPreferences.getInstance()).remove('token');
    notifyListeners();
  }
}
