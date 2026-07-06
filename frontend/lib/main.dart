import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localized_locales/flutter_localized_locales.dart';
import 'package:provider/provider.dart';
import 'package:world_countries/world_countries.dart';

import 'api/api_client.dart';
import 'design/app_theme.dart';
import 'l10n/app_localizations.dart';
import 'screens/app_shell.dart';
import 'screens/login_screen.dart';
import 'screens/reset_password_screen.dart';
import 'screens/update_required_screen.dart';
import 'state/auth.dart';
import 'state/settings.dart';
import 'util/native_drag.dart';
import 'widgets/android_install_banner.dart';
import 'widgets/update_banner.dart';

void main() {
  // Must run before any plugin used pre-runApp: SharedPreferences in
  // SettingsController.load() and secure storage in AuthController.restore().
  // On ALL platforms, not just web — without it on mobile, load()/restore() fire
  // before the binding is ready, throw silently, and the persisted language/theme
  // selection (and session) are lost on restart.
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) {
    // On web, suppress the browser's native context menu so a long-press / right
    // click on a card shows only our own action sheet, not the browser's menu.
    BrowserContextMenu.disableContextMenu();
    // Stop the browser hijacking mouse-drags as native drag-and-drop, which
    // otherwise withholds pointermove events and breaks rail drag-scrolling.
    preventNativeDrag();
  }
  final api = ApiClient();
  final settings = SettingsController(api)..load();
  final auth = AuthController(api)
    // Server-stored languages follow the user across devices: hydrate the local
    // cache from the profile whenever it (re)loads.
    ..onMe = ((me) => settings.hydrateFromServer(me.languages))
    // On signup, seed the account's primary language from the device (if we ship
    // that translation) so the user reads everything in their language right away,
    // without visiting settings. Done once; changeable later in settings.
    ..onRegistered = ((me) async {
      final device = settings.deviceContentLanguage();
      if (device != null) await settings.setLanguages([device]);
    })
    ..restore();
  runApp(
    MultiProvider(
      providers: [
        // ApiClient is a ChangeNotifier (it fires after authenticated writes so
        // screens can auto-refresh). `.value` provides the shared instance without
        // disposing it — `main` owns it and hands the same one to the controllers.
        ChangeNotifierProvider<ApiClient>.value(value: api),
        ChangeNotifierProvider<AuthController>.value(value: auth),
        ChangeNotifierProvider<SettingsController>.value(value: settings),
      ],
      child: const CinetrackApp(),
    ),
  );
}

class CinetrackApp extends StatelessWidget {
  const CinetrackApp({super.key});
  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    return MaterialApp(
      title: 'Cinetrack',
      navigatorKey: AuthController.navigatorKey,
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        LocaleNamesLocalizationsDelegate(), // CLDR-localized language names
        TypedLocaleDelegate(), // CLDR-localized country/territory names
        ...AppLocalizations.localizationsDelegates,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      locale: settings.locale,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: settings.themeMode,
      // Above every route: an install-the-app nudge that only renders on
      // web-Android (no-op otherwise), pointing at the matching-version APK.
      builder: (context, child) => Column(
        // Stretch so routes get a tight, finite width. Without this the Column
        // hands children a loose/unbounded width, which makes Rows with Expanded
        // children (e.g. the invites screen) throw "infinite width" on layout.
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const UpdateBanner(),
          const AndroidInstallBanner(),
          Expanded(child: child ?? const SizedBox.shrink()),
        ],
      ),
      home: const RootView(),
    );
  }
}

/// Chooses the first screen. Handles the web password-reset deep link
/// (`/reset-password?token=...`) before falling back to auth-gated routing.
class RootView extends StatefulWidget {
  const RootView({super.key});
  @override
  State<RootView> createState() => _RootViewState();
}

class _RootViewState extends State<RootView> {
  String? _resetToken;
  String? _inviteCode;
  StreamSubscription<Uri>? _linkSub;

  @override
  void initState() {
    super.initState();
    // Web: the launch URL is in Uri.base.
    _handleUri(Uri.base);
    // Native: the App Link / Universal Link that opened the app (cold start) plus
    // any that arrive while it's running, via the platform intent.
    if (!kIsWeb) {
      final links = AppLinks();
      links.getInitialLink().then((uri) {
        if (uri != null) _handleUri(uri);
      });
      _linkSub = links.uriLinkStream.listen(_handleUri);
    }
  }

  /// Route a deep link (from the web launch URL or a native intent) to the right
  /// screen. Unrecognized links just open the app normally.
  void _handleUri(Uri uri) {
    if (uri.path.contains('reset-password')) {
      final tok = uri.queryParameters['token'];
      if (tok != null && tok.isNotEmpty) {
        setState(() => _resetToken = tok);
        return;
      }
    }
    final invite = uri.queryParameters['invite'];
    if (invite != null && invite.isNotEmpty) {
      setState(() => _inviteCode = invite);
    }
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthController>(
      builder: (context, auth, _) {
        if (auth.loading) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        // A forced update blocks everything (deep links included) until the user updates.
        if (auth.updateRequired) return const UpdateRequiredScreen();
        if (_resetToken != null) {
          return ResetPasswordScreen(
            token: _resetToken!,
            onDone: () => setState(() => _resetToken = null),
          );
        }
        return auth.isAuthed ? const AppShell() : LoginScreen(initialInvite: _inviteCode);
      },
    );
  }
}
