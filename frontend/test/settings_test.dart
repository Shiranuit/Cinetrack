import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/state/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('selected languages persist across app restarts', () async {
    SharedPreferences.setMockInitialValues({});

    // Session 1: add French alongside English.
    final s1 = SettingsController();
    await s1.setLanguages(['eng', 'fra']);
    expect(s1.languages, ['eng', 'fra']);

    // Session 2 (restart): a fresh controller loads from storage.
    final s2 = SettingsController();
    await s2.load();
    expect(s2.languages, ['eng', 'fra'], reason: 'languages should survive a restart');
  });
}
