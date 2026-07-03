import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/design/app_theme.dart';
import 'package:frontend/screens/login_screen.dart';

void main() {
  testWidgets('login screen renders with the brand + theme', (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(theme: AppTheme.dark(), home: const LoginScreen()));
    expect(find.text('CINETRACK'), findsOneWidget);
    expect(find.text('Log in'), findsWidgets);
  });
}
