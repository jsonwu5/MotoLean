import 'dart:math' as math;

import '../utils/geo.dart';

/// 一个速度采样点。零百测试只关心时间、速度、精度、位置与海拔。
class AccelerationPoint {
  const AccelerationPoint({
    required this.tMs,
    required this.speedMps,
    this.accuracyM,
    this.lat,
    this.lon,
    this.altitudeM,
  });

  final int tMs;
  final double speedMps;
  final double? accuracyM;
  final double? lat;
  final double? lon;
  final double? altitudeM;

  bool get hasPosition => lat != null && lon != null;
}

/// 一次零百计算的结果。
class AccelerationResult {
  const AccelerationResult({
    this.resultMs,
    this.result60Ms,
    this.result130Ms,
    this.result200Ms,
    this.distanceM,
    this.maxSpeedMps,
    this.gradePercent,
    this.medianAccuracyM,
    this.startLat,
    this.startLon,
    this.valid = true,
    this.invalidReason,
    this.sampleCount = 0,
  });

  /// 0 → 目标速度（毫秒）。未达目标时为 null。
  final int? resultMs;
  final int? result60Ms;
  final int? result130Ms;
  final int? result200Ms;
  final double? distanceM;
  final double? maxSpeedMps;
  final double? gradePercent;
  final double? medianAccuracyM;
  final double? startLat;
  final double? startLon;
  final bool valid;
  final String? invalidReason;
  final int sampleCount;

  bool get hasResult => resultMs != null;

  double? get resultSeconds => resultMs == null ? null : resultMs! / 1000;
}

/// 零百计时算法（纯 Dart，可单测，不依赖任何平台通道）。
///
/// 手机 GPS 通常 1 Hz，一次 0–100 只有 5–8 个速度点，必须用**线性插值**
/// 求精确达速时刻；直接用采样点会带来 0.4–0.6 s 误差。
class AccelerationTimer {
  const AccelerationTimer._();

  /// 从静止起算的起步阈值（≈1.8 km/h）。
  static const double startSpeedMps = 0.5;

  /// 1 英尺 rollout 的起步阈值。
  ///
  /// 语义：车已移动约 1 英尺（0.3048 m）后才开始计时，所以比静止口径**更晚**，
  /// 成绩更短。用速度阈值近似位移：`v = sqrt(2·a·0.3048)`，加速度取
  /// 5–6 m/s² 时约 1.8 m/s（≈6.5 km/h）。1 Hz GPS 无法可靠测量 1 英尺位移，
  /// 这是手机端能做到的合理近似。
  static const double rolloutStartSpeedMps = 1.8;

  /// 相邻样本间隔超过该值即视为定位中断。
  static const int maxGapMs = 1500;

  /// 起步前若已在移动（前 3 秒平均速度超过该值），判定「没停稳」。
  static const double stationarySpeedMps = 1.0;

  /// 达速前速度相对峰值回落超过该比例，判定为打滑/松油门。
  static const double slipDropRatio = 0.15;

  static const double target60Kmh = 60;
  static const double target100Kmh = 100;
  static const double target130Kmh = 130;
  static const double target200Kmh = 200;

  /// 计算成绩。
  ///
  /// [samples] 必须按时间升序；[targetSpeedKmh] 是主目标（通常 100）。
  static AccelerationResult compute({
    required List<AccelerationPoint> samples,
    double targetSpeedKmh = target100Kmh,
    bool rollout = false,
    double accuracyLimitM = 35,
  }) {
    if (samples.length < 3) {
      return const AccelerationResult(
        valid: false,
        invalidReason: '有效定位数据不足',
      );
    }

    // 1. 过滤明显无效的样本：非有限值、负速度、精度超限。
    final filtered = <AccelerationPoint>[];
    for (final sample in samples) {
      if (!sample.speedMps.isFinite || sample.speedMps < 0) {
        continue;
      }
      final accuracy = sample.accuracyM;
      if (accuracy != null && accuracy > accuracyLimitM) {
        continue;
      }
      filtered.add(sample);
    }
    if (filtered.length < 3) {
      return AccelerationResult(
        valid: false,
        invalidReason: '定位精度不足',
        sampleCount: filtered.length,
      );
    }

    // 2. 数据连续性检查。
    for (var i = 1; i < filtered.length; i++) {
      if (filtered[i].tMs - filtered[i - 1].tMs > maxGapMs) {
        return AccelerationResult(
          valid: false,
          invalidReason: '定位数据中断',
          sampleCount: filtered.length,
        );
      }
    }

    final accuracyValues = [
      for (final sample in filtered)
        if (sample.accuracyM != null) sample.accuracyM!,
    ];
    final medianAccuracy = accuracyValues.isEmpty
        ? null
        : _median(accuracyValues);

    final maxSpeed = filtered
        .map((sample) => sample.speedMps)
        .reduce((a, b) => a > b ? a : b);

    // 3. 起步时刻。
    final startMps = rollout ? rolloutStartSpeedMps : startSpeedMps;
    final startMs = _crossTimeMs(filtered, startMps);
    if (startMs == null) {
      return AccelerationResult(
        valid: false,
        invalidReason: '未检测到起步',
        sampleCount: filtered.length,
        medianAccuracyM: medianAccuracy,
        maxSpeedMps: maxSpeed,
      );
    }

    // 4. 起步前是否已经停稳：
    //    - 首个样本速度就已经很高，说明开始记录时车已在动；
    //    - 或者起步前 3 秒的平均速度偏高。
    final first = filtered.first;
    if (first.tMs >= startMs && first.speedMps > stationarySpeedMps) {
      return AccelerationResult(
        valid: false,
        invalidReason: '起步前车辆未静止',
        sampleCount: filtered.length,
        medianAccuracyM: medianAccuracy,
        maxSpeedMps: maxSpeed,
      );
    }
    final beforeStart = filtered
        .where((sample) => sample.tMs < startMs && sample.tMs >= startMs - 3000)
        .toList();
    if (beforeStart.isNotEmpty) {
      final avg = beforeStart
              .map((sample) => sample.speedMps)
              .reduce((a, b) => a + b) /
          beforeStart.length;
      if (avg > stationarySpeedMps) {
        return AccelerationResult(
          valid: false,
          invalidReason: '起步前车辆未静止',
          sampleCount: filtered.length,
          medianAccuracyM: medianAccuracy,
          maxSpeedMps: maxSpeed,
        );
      }
    }

    // 5. 各目标速度的达速时刻。
    final targetMps = targetSpeedKmh / 3.6;
    final targetMs = _crossTimeMs(filtered, targetMps, fromMs: startMs);
    final cross60 = _crossTimeMs(filtered, target60Kmh / 3.6, fromMs: startMs);
    final cross130 = _crossTimeMs(filtered, target130Kmh / 3.6, fromMs: startMs);
    final cross200 = _crossTimeMs(filtered, target200Kmh / 3.6, fromMs: startMs);

    if (targetMs == null) {
      return AccelerationResult(
        valid: false,
        invalidReason: '未达到目标速度',
        sampleCount: filtered.length,
        medianAccuracyM: medianAccuracy,
        maxSpeedMps: maxSpeed,
        result60Ms: cross60 == null ? null : cross60 - startMs,
        result130Ms: (cross60 == null || cross130 == null)
            ? null
            : cross130 - cross60,
      );
    }

    // 6. 打滑检测：达标前速度相对峰值回落超过阈值。
    final racing = filtered
        .where((sample) => sample.tMs >= startMs && sample.tMs <= targetMs)
        .toList();
    var peak = 0.0;
    var slip = false;
    for (final sample in racing) {
      if (sample.speedMps >= peak) {
        peak = sample.speedMps;
      } else if (peak > 0 && sample.speedMps < peak * (1 - slipDropRatio)) {
        slip = true;
        break;
      }
    }
    if (slip) {
      return AccelerationResult(
        valid: false,
        invalidReason: '检测到速度回落（可能打滑或松油门）',
        sampleCount: filtered.length,
        medianAccuracyM: medianAccuracy,
        maxSpeedMps: maxSpeed,
        result60Ms: cross60 == null ? null : cross60 - startMs,
      );
    }

    // 7. 派生指标：起步距离与平均坡度。
    final window = filtered
        .where((sample) => sample.tMs >= startMs && sample.tMs <= targetMs)
        .toList();
    final distance = _distanceMeters(window);
    final grade = _gradePercent(window, distance);
    AccelerationPoint? startPoint;
    for (final sample in filtered) {
      if (sample.tMs <= startMs) {
        startPoint = sample;
      } else {
        break;
      }
    }

    return AccelerationResult(
      resultMs: targetMs - startMs,
      result60Ms: cross60 == null ? null : cross60 - startMs,
      result130Ms:
          (cross60 == null || cross130 == null) ? null : cross130 - cross60,
      result200Ms: cross200 == null ? null : cross200 - startMs,
      distanceM: distance,
      maxSpeedMps: maxSpeed,
      gradePercent: grade,
      medianAccuracyM: medianAccuracy,
      startLat: startPoint?.lat,
      startLon: startPoint?.lon,
      sampleCount: filtered.length,
    );
  }

  /// 找到速度首次达到 [targetMps] 的插值时刻。
  static int? _crossTimeMs(
    List<AccelerationPoint> samples,
    double targetMps, {
    int fromMs = 0,
  }) {
    for (var i = 0; i < samples.length; i++) {
      final sample = samples[i];
      if (sample.tMs < fromMs) {
        continue;
      }
      if (sample.speedMps < targetMps) {
        continue;
      }
      if (i == 0) {
        // 第一个样本就已经超过阈值：没有更早的数据可以插值。
        return sample.tMs;
      }
      final previous = samples[i - 1];
      final delta = sample.speedMps - previous.speedMps;
      if (delta <= 0) {
        return sample.tMs;
      }
      final fraction = (targetMps - previous.speedMps) / delta;
      final clamped = fraction.clamp(0.0, 1.0).toDouble();
      return (previous.tMs + (sample.tMs - previous.tMs) * clamped).round();
    }
    return null;
  }

  static double? _distanceMeters(List<AccelerationPoint> window) {
    var total = 0.0;
    double? lastLat;
    double? lastLon;
    var counted = 0;
    for (final sample in window) {
      if (!sample.hasPosition) {
        continue;
      }
      if (lastLat != null && lastLon != null) {
        total += distanceMeters(lastLat, lastLon, sample.lat!, sample.lon!);
        counted++;
      }
      lastLat = sample.lat;
      lastLon = sample.lon;
    }
    return counted == 0 ? null : total;
  }

  /// 平均坡度：海拔差 / 水平距离 × 100%。
  ///
  /// 海拔噪声大，两端各取一个窗口做平均，避免单点抖动放大成陡坡。
  static double? _gradePercent(
    List<AccelerationPoint> window,
    double? distanceM,
  ) {
    if (distanceM == null || distanceM < 10) {
      return null;
    }
    final withAltitude = window
        .where((sample) => sample.altitudeM != null)
        .toList();
    if (withAltitude.length < 2) {
      return null;
    }
    final headCount = math.min(3, withAltitude.length);
    final tailCount = math.min(3, withAltitude.length);
    final head = withAltitude.take(headCount).toList();
    final tail = withAltitude.skip(withAltitude.length - tailCount).toList();
    final headAvg = head
            .map((sample) => sample.altitudeM!)
            .reduce((a, b) => a + b) /
        head.length;
    final tailAvg = tail
            .map((sample) => sample.altitudeM!)
            .reduce((a, b) => a + b) /
        tail.length;
    return (tailAvg - headAvg) / distanceM * 100;
  }

  static double _median(List<double> values) {
    final sorted = List<double>.of(values)..sort();
    final middle = sorted.length ~/ 2;
    if (sorted.length.isOdd) {
      return sorted[middle];
    }
    return (sorted[middle - 1] + sorted[middle]) / 2;
  }
}
