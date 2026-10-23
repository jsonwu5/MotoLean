import 'dart:math' as math;

/// A three-component sensor reading.
class Vec3 {
  const Vec3(this.x, this.y, this.z);

  final double x;
  final double y;
  final double z;

  double get magnitude => math.sqrt(x * x + y * y + z * z);

  Vec3 operator +(Vec3 other) => Vec3(x + other.x, y + other.y, z + other.z);

  Vec3 operator /(double divisor) => Vec3(x / divisor, y / divisor, z / divisor);

  @override
  String toString() => 'Vec3(${x.toStringAsFixed(2)}, '
      '${y.toStringAsFixed(2)}, ${z.toStringAsFixed(2)})';
}

/// How the phone is mounted. The estimator needs the phone's X axis to point
/// to the rider's right.
enum LeanMount {
  /// Portrait, screen facing the rider, top of the phone pointing up.
  verticalScreenFacingRider,

  /// Lying flat, screen up, top of the phone pointing forward.
  flatScreenUpTopForward,
}

/// Result of the stationary calibration.
///
/// Roll is positive when the bike leans to the right and negative to the left.
/// The accelerometer gives an absolute roll estimate; the gyroscope component
/// around the bike's longitudinal axis gives the short-term rate.
class LeanCalibration {
  const LeanCalibration({
    required this.accelSampleCount,
    required this.gravityMagnitude,
    required this.zeroRollDeg,
    required this.mount,
    required this.gyroAxisIndex,
    required this.gyroAxisSign,
    required this.gyroBiasRaw,
    required this.usable,
    this.warning,
  });

  final int accelSampleCount;
  final double gravityMagnitude;
  final double zeroRollDeg;
  final LeanMount mount;

  /// 1 = Y axis, 2 = Z axis of the gyroscope.
  final int gyroAxisIndex;

  /// Convert the raw gyro value into "positive means leaning right".
  final double gyroAxisSign;

  /// Raw gyro value measured while stationary, in rad/s.
  final double gyroBiasRaw;

  final bool usable;
  final String? warning;

  static LeanCalibration fromSamples({
    required List<Vec3> accelSamples,
    required List<Vec3> gyroSamples,
  }) {
    if (accelSamples.isEmpty) {
      return const LeanCalibration(
        accelSampleCount: 0,
        gravityMagnitude: 0.0,
        zeroRollDeg: 0.0,
        mount: LeanMount.verticalScreenFacingRider,
        gyroAxisIndex: 2,
        gyroAxisSign: -1,
        gyroBiasRaw: 0.0,
        usable: false,
        warning: '没有读取到加速度计数据',
      );
    }

    var sum = const Vec3(0, 0, 0);
    for (final sample in accelSamples) {
      sum = sum + sample;
    }
    final mean = sum / accelSamples.length.toDouble();
    final mount = mean.z.abs() > mean.y.abs()
        ? LeanMount.flatScreenUpTopForward
        : LeanMount.verticalScreenFacingRider;
    final gyroAxisIndex = mount == LeanMount.flatScreenUpTopForward ? 1 : 2;

    // Vertical mount: the phone's Z axis points backwards, so a right-hand
    // lean produces a negative Z gyro reading. Flat mount: the phone's Y axis
    // points forward, so a right-hand lean produces a positive Y reading.
    final gyroAxisSign = mount == LeanMount.flatScreenUpTopForward ? 1.0 : -1.0;

    var gyroSum = 0.0;
    for (final sample in gyroSamples) {
      gyroSum += gyroAxisIndex == 1 ? sample.y : sample.z;
    }
    final gyroBias =
        gyroSamples.isEmpty ? 0.0 : gyroSum / gyroSamples.length.toDouble();

    final zeroRollDeg = _degrees(
      math.atan2(-mean.x, math.sqrt(mean.y * mean.y + mean.z * mean.z)),
    );

    // Motion during calibration: compare individual roll estimates to mean.
    var maxDeviation = 0.0;
    for (final sample in accelSamples) {
      final roll = _degrees(
        math.atan2(-sample.x, math.sqrt(sample.y * sample.y + sample.z * sample.z)),
      );
      maxDeviation = math.max(maxDeviation, (roll - zeroRollDeg).abs());
    }

    final gravity = mean.magnitude;
    final usable = accelSamples.length >= 20 && gravity > 5 && gravity < 15;
    final verticalAxis = mean.y.abs();
    final flatAxis = mean.z.abs();
    final axisRatio = verticalAxis > flatAxis
        ? verticalAxis / math.max(flatAxis, 0.001)
        : flatAxis / math.max(verticalAxis, 0.001);
    String? warning;
    if (!usable) {
      warning = '传感器数据不足或重力读数异常，请扶正车身保持静止后重试';
    } else if (mean.x.abs() > 3) {
      warning = '手机左右方向倾斜较大，建议调整支架后重新校准';
    } else if (axisRatio < 1.5) {
      warning = '手机接近 45° 斜放，建议按竖装或平放固定后重新校准';
    } else if (maxDeviation > 8) {
      warning = '校准期间检测到移动，本次零位可能有偏差';
    } else if (gyroSamples.isEmpty) {
      warning = '未读取到陀螺仪数据，倾角响应会变慢';
    }

    return LeanCalibration(
      accelSampleCount: accelSamples.length,
      gravityMagnitude: gravity,
      zeroRollDeg: zeroRollDeg,
      mount: mount,
      gyroAxisIndex: gyroAxisIndex,
      gyroAxisSign: gyroAxisSign,
      gyroBiasRaw: gyroBias,
      usable: usable,
      warning: warning,
    );
  }
}

/// Fuses accelerometer roll with gyroscope roll rate.
///
/// The accelerometer is accurate in steady corners but noisy over bumps and
/// under braking. The gyroscope is smooth and fast but drifts. A
/// complementary filter keeps the best of both: the gyro predicts each
/// sample, the accelerometer slowly corrects the prediction.
class LeanAngleEstimator {
  LeanCalibration? _calibration;
  double _filteredRollDeg = 0;
  double _accelRollLowPassDeg = 0;
  bool _hasAccel = false;

  LeanCalibration? get calibration => _calibration;
  double get rollDeg => _filteredRollDeg;

  void reset(LeanCalibration calibration) {
    _calibration = calibration;
    _filteredRollDeg = 0;
    _accelRollLowPassDeg = 0;
    _hasAccel = false;
  }

  /// Call from the accelerometer stream. [gyro] is the latest gyroscope
  /// reading and [dtSeconds] is the time since the previous accelerometer
  /// sample.
  double update({
    required Vec3 accel,
    Vec3? gyro,
    required double dtSeconds,
  }) {
    final calibration = _calibration;
    if (calibration == null) {
      return 0;
    }
    final dt = dtSeconds.clamp(0.002, 0.1).toDouble();

    final gravity = accel.magnitude;
    final accelRollDeg = _degrees(
          math.atan2(-accel.x, math.sqrt(accel.y * accel.y + accel.z * accel.z)),
        ) -
        calibration.zeroRollDeg;

    if (!_hasAccel) {
      _accelRollLowPassDeg = accelRollDeg;
      _hasAccel = true;
    } else {
      // Smooth accelerometer noise without adding noticeable lag. The
      // complementary filter does the heavy lifting below.
      _accelRollLowPassDeg += 0.35 * (accelRollDeg - _accelRollLowPassDeg);
    }

    var rateDegPerSec = 0.0;
    if (gyro != null) {
      final raw = calibration.gyroAxisIndex == 1 ? gyro.y : gyro.z;
      final rateRad = raw - calibration.gyroBiasRaw;
      rateDegPerSec = calibration.gyroAxisSign * _degrees(rateRad);
    }

    final predicted = _filteredRollDeg + rateDegPerSec * dt;

    // Reject accelerometer corrections during hard bumps, drops, or free
    // fall. The gyro keeps the estimate alive in those moments.
    final accelTrusted = gravity > 6.5 && gravity < 13.5;

    if (!accelTrusted) {
      _filteredRollDeg = predicted;
    } else {
      final error = (_accelRollLowPassDeg - predicted).abs();
      // During quick transitions trust the gyro almost completely; in steady
      // state follow the accelerometer with roughly a 0.35 s time constant.
      final tau = error > 18 ? 1.2 : 0.35;
      final alpha = tau / (tau + dt);
      _filteredRollDeg = alpha * predicted + (1 - alpha) * _accelRollLowPassDeg;
    }

    _filteredRollDeg = _filteredRollDeg.clamp(-65.0, 65.0).toDouble();
    return _filteredRollDeg;
  }
}

double _degrees(double radians) => radians * 180.0 / math.pi;
