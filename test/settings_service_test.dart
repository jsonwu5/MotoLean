import 'package:flutter_test/flutter_test.dart';
import 'package:motolean/services/settings_service.dart';
import 'package:motolean/utils/units.dart';

void main() {
  group('SettingsService 默认值', () {
    test('未加载时使用公制与默认阈值', () {
      final settings = SettingsService();
      expect(settings.speedUnit, SpeedUnit.kmh);
      expect(settings.distanceUnit, DistanceUnit.km);
      expect(settings.elevationUnit, ElevationUnit.m);
      expect(settings.calibrationSeconds, 3);
      expect(settings.gpsAccuracyLimit, 35);
      expect(settings.defaultScreenAwake, isFalse);
      expect(settings.confirmBeforeStop, isTrue);
      expect(settings.accelTargetSpeedKmh, 100);
      expect(settings.accelRollout, isFalse);
      expect(settings.accelCountdownSeconds, 3);
      expect(settings.accelRecordTrack, isTrue);
      expect(settings.showLiveTrack, isTrue);
      expect(settings.mapStyle, MapStyle.standard);
    });

    test('英制距离会让海拔自动切到英尺', () async {
      final settings = SettingsService();
      await settings.setDistanceUnit(DistanceUnit.mi);
      expect(settings.elevationUnit, ElevationUnit.ft);
    });
  });

  group('SettingsService 取值校验', () {
    test('GPS 精度阈值被限制在 10–50 米', () async {
      final settings = SettingsService();
      await settings.setGpsAccuracyLimit(200);
      expect(settings.gpsAccuracyLimit, 50);
      await settings.setGpsAccuracyLimit(-5);
      expect(settings.gpsAccuracyLimit, 10);
      await settings.setGpsAccuracyLimit(22);
      expect(settings.gpsAccuracyLimit, 22);
    });

    test('非法的校准时长回退到 3 秒', () async {
      final settings = SettingsService();
      await settings.setCalibrationSeconds(7);
      expect(settings.calibrationSeconds, 3);
      await settings.setCalibrationSeconds(5);
      expect(settings.calibrationSeconds, 5);
    });

    test('非法的目标速度回退到 100 km/h', () async {
      final settings = SettingsService();
      await settings.setAccelTargetSpeedKmh(80);
      expect(settings.accelTargetSpeedKmh, 100);
      await settings.setAccelTargetSpeedKmh(200);
      expect(settings.accelTargetSpeedKmh, 200);
    });

    test('非法的倒计时回退到 3 秒', () async {
      final settings = SettingsService();
      await settings.setAccelCountdownSeconds(7);
      expect(settings.accelCountdownSeconds, 3);
      await settings.setAccelCountdownSeconds(0);
      expect(settings.accelCountdownSeconds, 0);
    });
  });

  group('SettingsService 通知与重置', () {
    test('修改设置会通知监听者', () async {
      final settings = SettingsService();
      var notified = 0;
      settings.addListener(() => notified++);

      await settings.setSpeedUnit(SpeedUnit.mph);
      expect(notified, 1);

      // 值没变就不重复通知。
      await settings.setSpeedUnit(SpeedUnit.mph);
      expect(notified, 1);
    });

    test('恢复默认设置会重置全部字段', () async {
      final settings = SettingsService();
      await settings.setSpeedUnit(SpeedUnit.mph);
      await settings.setDistanceUnit(DistanceUnit.mi);
      await settings.setAccelRollout(true);
      await settings.setMapStyle(MapStyle.dark);

      await settings.resetToDefaults();

      expect(settings.speedUnit, SpeedUnit.kmh);
      expect(settings.distanceUnit, DistanceUnit.km);
      expect(settings.accelRollout, isFalse);
      expect(settings.mapStyle, MapStyle.standard);
    });
  });

  group('单位换算', () {
    test('速度单位换算与格式化', () {
      const mps = 27.7778; // 100 km/h
      expect(formatSpeedValue(mps, SpeedUnit.kmh), '100');
      expect(formatSpeedValue(mps, SpeedUnit.mph), '62');
      expect(formatSpeedWithUnit(mps, SpeedUnit.kmh), '100 km/h');
      expect(formatSpeedWithUnit(mps, SpeedUnit.mph), '62 mph');
    });

    test('距离单位在小距离与大距离之间切换', () {
      expect(formatDistanceWithUnit(850, DistanceUnit.km), '850 m');
      expect(formatDistanceWithUnit(21800, DistanceUnit.km), '21.8 km');
      expect(formatDistanceWithUnit(1609.344, DistanceUnit.mi), '1.00 mi');
      expect(formatDistanceWithUnit(100, DistanceUnit.mi), '328 ft');
    });

    test('海拔单位换算', () {
      expect(formatElevationWithUnit(380, ElevationUnit.m), '380 m');
      expect(formatElevationWithUnit(100, ElevationUnit.ft), '328 ft');
    });
  });
}
