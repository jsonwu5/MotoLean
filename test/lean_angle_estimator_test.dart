import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:motolean/services/lean_angle_estimator.dart';

Vec3 accelForLean(double leanDeg, LeanMount mount) {
  final radians = leanDeg * math.pi / 180;
  const g = 9.81;
  return mount == LeanMount.flatScreenUpTopForward
      ? Vec3(-g * math.sin(radians), 0, g * math.cos(radians))
      : Vec3(-g * math.sin(radians), g * math.cos(radians), 0);
}

Vec3 gyroForRate(double rateDegPerSec, LeanMount mount) {
  final radians = rateDegPerSec * math.pi / 180;
  return mount == LeanMount.flatScreenUpTopForward
      ? Vec3(0, radians, 0)
      : Vec3(0, 0, -radians);
}

LeanCalibration calibrateAtZero(LeanMount mount, {double gyroBias = 0}) {
  final accel = <Vec3>[];
  final gyro = <Vec3>[];
  for (var i = 0; i < 150; i++) {
    accel.add(accelForLean(0, mount));
    gyro.add(gyroForRate(0, mount) +
        (mount == LeanMount.flatScreenUpTopForward
            ? Vec3(0, gyroBias, 0)
            : Vec3(0, 0, gyroBias)));
  }
  return LeanCalibration.fromSamples(accelSamples: accel, gyroSamples: gyro);
}

void feedRamp({
  required LeanAngleEstimator estimator,
  required LeanMount mount,
  required double fromDeg,
  required double toDeg,
  required double rateDegPerSec,
  required double dt,
}) {
  final steps = ((toDeg - fromDeg).abs() / rateDegPerSec / dt).round();
  final direction = toDeg >= fromDeg ? 1.0 : -1.0;
  var lean = fromDeg;
  for (var i = 0; i < steps; i++) {
    lean += rateDegPerSec * dt * direction;
    estimator.update(
      accel: accelForLean(lean, mount),
      gyro: gyroForRate(rateDegPerSec * direction, mount),
      dtSeconds: dt,
    );
  }
}

void hold({
  required LeanAngleEstimator estimator,
  required LeanMount mount,
  required double leanDeg,
  required double seconds,
  required double dt,
  double gyroBias = 0,
}) {
  final bias = mount == LeanMount.flatScreenUpTopForward
      ? Vec3(0, gyroBias, 0)
      : Vec3(0, 0, gyroBias);
  final steps = (seconds / dt).round();
  for (var i = 0; i < steps; i++) {
    estimator.update(
      accel: accelForLean(leanDeg, mount),
      gyro: gyroForRate(0, mount) + bias,
      dtSeconds: dt,
    );
  }
}

void main() {
  const dt = 0.02;

  group('calibration', () {
    test('detects vertical mount and its axis convention', () {
      final calibration = calibrateAtZero(LeanMount.verticalScreenFacingRider);
      expect(calibration.usable, isTrue);
      expect(calibration.mount, LeanMount.verticalScreenFacingRider);
      expect(calibration.gyroAxisIndex, 2);
      expect(calibration.gyroAxisSign, -1);
      expect(calibration.zeroRollDeg, closeTo(0, 0.1));
    });

    test('detects flat mount and its axis convention', () {
      final calibration = calibrateAtZero(LeanMount.flatScreenUpTopForward);
      expect(calibration.usable, isTrue);
      expect(calibration.mount, LeanMount.flatScreenUpTopForward);
      expect(calibration.gyroAxisIndex, 1);
      expect(calibration.gyroAxisSign, 1);
    });

    test('stores gyro bias', () {
      final calibration =
          calibrateAtZero(LeanMount.verticalScreenFacingRider, gyroBias: 0.02);
      expect(calibration.gyroBiasRaw, closeTo(0.02, 1e-6));
    });

    test('rejects empty samples', () {
      final calibration = LeanCalibration.fromSamples(
        accelSamples: const [],
        gyroSamples: const [],
      );
      expect(calibration.usable, isFalse);
    });
  });

  group('lean angle estimator', () {
    for (final mount in LeanMount.values) {
      test('tracks a right-hand 30 degree corner ($mount)', () {
        final estimator =
            LeanAngleEstimator()..reset(calibrateAtZero(mount));
        hold(
          estimator: estimator,
          mount: mount,
          leanDeg: 0,
          seconds: 0.5,
          dt: dt,
        );
        feedRamp(
          estimator: estimator,
          mount: mount,
          fromDeg: 0,
          toDeg: 30,
          rateDegPerSec: 50,
          dt: dt,
        );
        hold(
          estimator: estimator,
          mount: mount,
          leanDeg: 30,
          seconds: 2.5,
          dt: dt,
        );
        expect(estimator.rollDeg, closeTo(30, 1.5));
      });

      test('tracks a left-hand 40 degree corner ($mount)', () {
        final estimator =
            LeanAngleEstimator()..reset(calibrateAtZero(mount));
        feedRamp(
          estimator: estimator,
          mount: mount,
          fromDeg: 0,
          toDeg: -40,
          rateDegPerSec: 60,
          dt: dt,
        );
        hold(
          estimator: estimator,
          mount: mount,
          leanDeg: -40,
          seconds: 2.5,
          dt: dt,
        );
        expect(estimator.rollDeg, closeTo(-40, 1.5));
      });

      test('returns to zero after the corner ($mount)', () {
        final estimator =
            LeanAngleEstimator()..reset(calibrateAtZero(mount));
        feedRamp(
          estimator: estimator,
          mount: mount,
          fromDeg: 0,
          toDeg: 35,
          rateDegPerSec: 60,
          dt: dt,
        );
        hold(
          estimator: estimator,
          mount: mount,
          leanDeg: 35,
          seconds: 2,
          dt: dt,
        );
        feedRamp(
          estimator: estimator,
          mount: mount,
          fromDeg: 35,
          toDeg: 0,
          rateDegPerSec: 60,
          dt: dt,
        );
        hold(
          estimator: estimator,
          mount: mount,
          leanDeg: 0,
          seconds: 2,
          dt: dt,
        );
        expect(estimator.rollDeg, closeTo(0, 1.5));
      });
    }

    test('subtracts gyro bias while stationary', () {
      final calibration =
          calibrateAtZero(LeanMount.verticalScreenFacingRider, gyroBias: 0.01);
      final estimator = LeanAngleEstimator()..reset(calibration);
      hold(
        estimator: estimator,
        mount: LeanMount.verticalScreenFacingRider,
        leanDeg: 0,
        seconds: 3,
        dt: dt,
        gyroBias: 0.01,
      );
      expect(estimator.rollDeg, closeTo(0, 0.05));
    });

    test('ignores a huge acceleration spike instead of flipping', () {
      final estimator = LeanAngleEstimator()
        ..reset(calibrateAtZero(LeanMount.verticalScreenFacingRider));
      hold(
        estimator: estimator,
        mount: LeanMount.verticalScreenFacingRider,
        leanDeg: 20,
        seconds: 2,
        dt: dt,
      );
      final before = estimator.rollDeg;
      // A 4 g bump along the lateral axis would look like a wild lean angle.
      estimator.update(
        accel: const Vec3(-35, 30, 0),
        gyro: const Vec3(0, 0, 0),
        dtSeconds: dt,
      );
      expect((estimator.rollDeg - before).abs(), lessThan(2));
    });
  });
}
