import 'package:flutter_test/flutter_test.dart';
import 'package:motolean/services/demo_ride.dart';
import 'package:motolean/utils/ride_analytics.dart';

void main() {
  group('demo ride', () {
    final ride = DemoRideGenerator.build(
      startedAt: DateTime(2026, 10, 1, 9, 30),
    );

    test('contains a full-length ride', () {
      expect(ride.samples.length, 1621);
      expect(ride.samples.last.tMs, 1620000);
      expect(ride.session.durationS, 1620);
      expect(ride.session.isDemo, isTrue);
      expect(ride.session.endedAt, isNotNull);
    });

    test('has a plausible distance and speed', () {
      expect(ride.session.distanceM, greaterThan(15000));
      expect(ride.session.distanceM, lessThan(45000));
      expect(ride.session.avgSpeedKmh, greaterThan(30));
      expect(ride.session.avgSpeedKmh, lessThan(90));
      expect(ride.session.elevationGainM, inInclusiveRange(150, 800));
      for (final sample in ride.samples) {
        expect(sample.speedMps, isNotNull);
        expect(sample.speedMps!, inInclusiveRange(5, 30));
      }
    });

    test('contains real left and right lean angles', () {
      expect(ride.session.maxLeanRightDeg, greaterThan(20));
      expect(ride.session.maxLeanLeftDeg, greaterThan(15));
      expect(ride.session.maxLeanRightDeg, lessThanOrEqualTo(48.01));
      expect(ride.session.maxLeanLeftDeg, lessThanOrEqualTo(48.01));
      expect(
        ride.samples.any((sample) => sample.leanDeg > 30),
        isTrue,
      );
      expect(
        ride.samples.any((sample) => sample.leanDeg < -25),
        isTrue,
      );
    });

    test('keeps moving through the end of the ride', () {
      final last = ride.samples.last;
      final earlier = ride.samples[ride.samples.length - 61];
      expect(last.lat, isNotNull);
      expect(earlier.lat, isNotNull);
      // The generator must not clamp at the end of its dense path.
      expect((last.lat! - earlier.lat!).abs() +
          (last.lon! - earlier.lon!).abs(), greaterThan(0.0001));
    });

    test('analytics agree with the generated summary', () {
      expect(
        RideAnalytics.maxLeanRight(ride.samples),
        closeTo(ride.session.maxLeanRightDeg, 0.02),
      );
      expect(
        RideAnalytics.maxLeanLeft(ride.samples),
        closeTo(ride.session.maxLeanLeftDeg, 0.02),
      );
      final bands = RideAnalytics.leanBands(ride.samples);
      expect(
        bands.fold<int>(0, (sum, band) => sum + band.seconds),
        ride.samples.length,
      );
      expect(RideAnalytics.cornerCount(ride.samples), greaterThan(10));
    });
  });
}
