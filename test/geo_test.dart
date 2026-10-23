import 'package:flutter_test/flutter_test.dart';
import 'package:motolean/utils/geo.dart';

void main() {
  group('distanceMeters', () {
    test('one degree of latitude at the equator', () {
      expect(distanceMeters(0, 0, 1, 0), closeTo(111195, 100));
    });

    test('zero distance for identical points', () {
      expect(distanceMeters(30.25, 119.72, 30.25, 119.72), closeTo(0, 0.001));
    });

    test('short distance is accurate', () {
      // ~111.3 m north.
      final distance = distanceMeters(30.2500, 119.7200, 30.2510, 119.7200);
      expect(distance, closeTo(111.3, 1));
    });
  });

  group('isPlausibleJump', () {
    test('accepts normal riding movement', () {
      expect(isPlausibleJump(distanceM: 30, elapsedSeconds: 1), isTrue);
    });

    test('rejects impossible GPS teleport', () {
      expect(isPlausibleJump(distanceM: 2000, elapsedSeconds: 1), isFalse);
    });

    test('rejects non-positive elapsed time', () {
      expect(isPlausibleJump(distanceM: 10, elapsedSeconds: 0), isFalse);
    });
  });
}
