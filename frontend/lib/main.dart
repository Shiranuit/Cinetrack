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
import 'state/auth.dart';
import 'state/settings.dart';

void main() {
  // On web, suppress the browser's native context menu so a long-press / right
  // click on a card shows only our own action sheet, not the browser's menu.
  if (kIsWeb) {
    WidgetsFlutterBinding.ensureInitialized();
    BrowserContextMenu.disableContextMenu();
  }
  final api = ApiClient();
  final auth = AuthController(api)..restore();
  final settings = SettingsController()..load();
  runApp(
    MultiProvider(
      providers: [
        Provider<ApiClient>.value(value: api),
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
      home: Consumer<AuthController>(
        builder: (context, auth, _) {
          if (auth.loading) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          return auth.isAuthed ? const AppShell() : const LoginScreen();
        },
      ),
    );
  }
}
