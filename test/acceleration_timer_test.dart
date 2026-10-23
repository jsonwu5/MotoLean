import 'package:flutter_test/flutter_test.dart';
import 'package:motolean/services/acceleration_timer.dart';

/// 构造一条「每秒增加 20 km/h」的线性加速曲线。
List<AccelerationPoint> _linearCurve({
  List<double> speedsKmh = const [0, 20, 40, 60, 80, 100, 120, 140],
  int stepMs = 1000,
}) {
  return [
    for (var i = 0; i < speedsKmh.length; i++)
      AccelerationPoint(
        tMs: i * stepMs,
        speedMps: speedsKmh[i] / 3.6,
        accuracyM: 5,
      ),
  ];
}

void main() {
  group('AccelerationTimer 计时', () {
    test('线性 0-100 插值结果正确', () {
      final result = AccelerationTimer.compute(
        samples: _linearCurve(),
        targetSpeedKmh: 100,
      );

      // 起步阈值 1.8 km/h 在 0→20 之间插值：90 ms。
      // 达速 100 恰好在 5000 ms，所以成绩应为 4910 ms。
      expect(result.valid, isTrue);
      expect(result.resultMs, isNotNull);
      expect((result.resultMs! - 4910).abs(), lessThanOrEqualTo(30));
      expect(result.hasResult, isTrue);
    });

    test('0-60 与 60-130 分段正确', () {
      final result = AccelerationTimer.compute(
        samples: _linearCurve(),
        targetSpeedKmh: 100,
      );

      // 60 km/h 在 3000 ms，减去起步插值点 90 ms。
      expect((result.result60Ms! - 2910).abs(), lessThanOrEqualTo(30));
      // 130 km/h 在 6000/6500 之间插值 = 6500 ms；130-60 = 3500 ms。
      expect((result.result130Ms! - 3500).abs(), lessThanOrEqualTo(30));
      // 最高只到 140，没有 0-200。
      expect(result.result200Ms, isNull);
    });

    test('rollout 口径比静止口径更快', () {
      final normal = AccelerationTimer.compute(
        samples: _linearCurve(),
        targetSpeedKmh: 100,
      );
      final rollout = AccelerationTimer.compute(
        samples: _linearCurve(),
        targetSpeedKmh: 100,
        rollout: true,
      );

      expect(normal.resultMs, isNotNull);
      expect(rollout.resultMs, isNotNull);
      final delta = normal.resultMs! - rollout.resultMs!;
      // 静止口径起步点在 1.8 km/h，rollout 在约 6.5 km/h，
      // 每秒 +20 km/h 的曲线上相差约 230 ms。
      expect(delta, greaterThan(150));
      expect(delta, lessThan(400));
    });

    test('采样点恰好落在阈值上时不产生偏差', () {
      final result = AccelerationTimer.compute(
        samples: _linearCurve(),
        targetSpeedKmh: 60,
      );
      expect((result.resultMs! - 2910).abs(), lessThanOrEqualTo(30));
    });
  });

  group('AccelerationTimer 有效性判定', () {
    test('未达到目标速度', () {
      final result = AccelerationTimer.compute(
        samples: _linearCurve(speedsKmh: [0, 20, 40, 60, 80, 90]),
        targetSpeedKmh: 100,
      );

      expect(result.valid, isFalse);
      expect(result.resultMs, isNull);
      expect(result.invalidReason, contains('未达到目标速度'));
    });

    test('速度回落判定为打滑', () {
      final result = AccelerationTimer.compute(
        samples: _linearCurve(speedsKmh: [0, 20, 40, 60, 45, 70, 100, 110]),
        targetSpeedKmh: 100,
      );

      expect(result.valid, isFalse);
      expect(result.invalidReason, contains('速度回落'));
    });

    test('定位空洞判定为数据中断', () {
      final samples = [
        AccelerationPoint(tMs: 0, speedMps: 0, accuracyM: 5),
        AccelerationPoint(tMs: 1000, speedMps: 10, accuracyM: 5),
        AccelerationPoint(tMs: 2000, speedMps: 20, accuracyM: 5),
        AccelerationPoint(tMs: 6000, speedMps: 28, accuracyM: 5),
        AccelerationPoint(tMs: 7000, speedMps: 30, accuracyM: 5),
      ];
      final result = AccelerationTimer.compute(
        samples: samples,
        targetSpeedKmh: 100,
      );

      expect(result.valid, isFalse);
      expect(result.invalidReason, contains('数据中断'));
    });

    test('起步时已在移动判定为未停稳', () {
      final result = AccelerationTimer.compute(
        samples: _linearCurve(speedsKmh: [30, 50, 70, 90, 110, 120]),
        targetSpeedKmh: 100,
      );

      expect(result.valid, isFalse);
      expect(result.invalidReason, contains('未静止'));
    });

    test('精度全部超限时判为有效数据不足', () {
      final samples = [
        for (var i = 0; i < 6; i++)
          AccelerationPoint(
            tMs: i * 1000,
            speedMps: i * 10,
            accuracyM: 80,
          ),
      ];
      final result = AccelerationTimer.compute(
        samples: samples,
        targetSpeedKmh: 100,
      );

      expect(result.valid, isFalse);
      expect(result.invalidReason, contains('精度不足'));
    });

    test('少于三个样本直接判无效', () {
      final result = AccelerationTimer.compute(
        samples: [
          AccelerationPoint(tMs: 0, speedMps: 0),
          AccelerationPoint(tMs: 1000, speedMps: 10),
        ],
        targetSpeedKmh: 100,
      );

      expect(result.valid, isFalse);
      expect(result.resultMs, isNull);
    });
  });

  group('AccelerationTimer 派生指标', () {
    test('未达目标时不计算距离', () {
      final samples = [
        for (var i = 0; i <= 4; i++)
          AccelerationPoint(
            tMs: i * 1000,
            speedMps: i * 5, // 最高 20 m/s = 72 km/h
            accuracyM: 5,
            lat: 30.4700,
            lon: 119.6300 + i * 0.0003,
            altitudeM: 100 + i * 4,
          ),
      ];
      final result = AccelerationTimer.compute(
        samples: samples,
        targetSpeedKmh: 100,
      );

      expect(result.valid, isFalse);
      expect(result.resultMs, isNull);
      expect(result.distanceM, isNull);
    });

    test('达标曲线能算出距离与正坡度', () {
      final samples = [
        for (var i = 0; i <= 8; i++)
          AccelerationPoint(
            tMs: i * 1000,
            speedMps: i * 5,
            accuracyM: 5,
            lat: 30.4700,
            lon: 119.6300 + i * 0.0003,
            altitudeM: 100 + i * 4,
          ),
      ];
      final result = AccelerationTimer.compute(
        samples: samples,
        targetSpeedKmh: 100,
        accuracyLimitM: 35,
      );

      expect(result.valid, isTrue);
      expect(result.distanceM, isNotNull);
      expect(result.distanceM!, greaterThan(50));
      expect(result.gradePercent, isNotNull);
      expect(result.gradePercent!, greaterThan(0));
      expect(result.medianAccuracyM, 5);
    });
  });
}
