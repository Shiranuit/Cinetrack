import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:frontend/api/api_client.dart';
import 'package:frontend/design/app_theme.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:frontend/screens/login_screen.dart';
import 'package:frontend/state/auth.dart';

void main() {
  testWidgets('login screen renders with the brand + theme', (WidgetTester tester) async {
    // LoginScreen needs the AuthController (for the feature flags) and the
    // localization delegates in its ancestry to build.
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthController>(
        create: (_) => AuthController(ApiClient()),
        child: MaterialApp(
          theme: AppTheme.dark(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const LoginScreen(),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('CINETRACK'), findsOneWidget);
    expect(find.text('Log in'), findsWidgets);
  });
}
