import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/config.dart';

void main() {
  group('isOlderVersion (optional "update available" banner)', () {
    test('handles the "v" prefix and its absence', () {
      expect(isOlderVersion('v0.2.3', 'v0.2.4'), isTrue);
      expect(isOlderVersion('0.2.3', '0.2.4'), isTrue); // no "v"
      expect(isOlderVersion('v0.2.3', '0.2.4'), isTrue); // mixed
    });
    test('equal / newer is not older', () {
      expect(isOlderVersion('v0.2.4', 'v0.2.4'), isFalse);
      expect(isOlderVersion('v0.3.0', 'v0.2.9'), isFalse);
    });
    test('non-release tags are ignored', () {
      expect(isOlderVersion('dev', 'v0.2.4'), isFalse);
      expect(isOlderVersion('v0.2.4', null), isFalse);
      expect(isOlderVersion('v1.0', 'v1.0.1'), isFalse); // not 3 parts
    });
  });

  group('isBreakingBehind (forced update)', () {
    test('0.x: a new MINOR is breaking, a PATCH is not', () {
      expect(isBreakingBehind('v0.2.9', 'v0.3.0'), isTrue); // minor bump -> force
      expect(isBreakingBehind('v0.2.0', 'v0.2.9'), isFalse); // patch -> no force
    });
    test('1.0+: a new MAJOR is breaking, a MINOR is not', () {
      expect(isBreakingBehind('v1.9.9', 'v2.0.0'), isTrue); // major bump -> force
      expect(isBreakingBehind('v1.4.0', 'v1.9.0'), isFalse); // minor -> no force
    });
    test('newer or equal client is never forced', () {
      expect(isBreakingBehind('v0.3.0', 'v0.2.0'), isFalse);
      expect(isBreakingBehind('v0.2.4', 'v0.2.4'), isFalse);
    });
    test('"v" prefix optional; non-tags ignored', () {
      expect(isBreakingBehind('0.2.9', 'v0.3.0'), isTrue);
      expect(isBreakingBehind('dev', 'v0.3.0'), isFalse);
      expect(isBreakingBehind('v0.2.9', null), isFalse);
    });
  });
}
