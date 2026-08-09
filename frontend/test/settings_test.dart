import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/api/models.dart';
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

  /// "Keep shows in To watch while episodes are still coming" is a SERVER
  /// preference, not a device one: the buckets are computed in SQL, so the choice
  /// has to reach the backend and follow the user across devices. The request
  /// itself is covered in api_notify_test.dart, which has no HTTP-stubbing binding.
  group('keep-upcoming-in-to-watch preference', () {
    test('an older server that omits the field means stock behaviour', () {
      final me = Me.fromJson(const {'id': 'u1', 'screen_name': 'someone'});
      expect(me.keepUpcomingInToWatch, isFalse,
          reason: 'a missing field must not rearrange the library');
    });

    test('the field round-trips when the server does send it', () {
      final me = Me.fromJson(const {
        'id': 'u1',
        'screen_name': 'someone',
        'keep_upcoming_in_to_watch': true,
      });
      expect(me.keepUpcomingInToWatch, isTrue);
    });
  });
}
