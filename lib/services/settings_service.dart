import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/units.dart';

/// 地图底图风格。
enum MapStyle {
  /// Esri 卫星影像（默认）。
  satellite('卫星影像'),

  /// 深色简约底图。
  dark('简约暗色');

  const MapStyle(this.label);

  final String label;

  static MapStyle fromName(String? name) {
    for (final style in MapStyle.values) {
      if (style.name == name) {
        return style;
      }
    }
    return MapStyle.satellite;
  }
}

/// 全局偏好设置。
///
/// 用 [ChangeNotifier] 暴露，凡是要响应设置变化的界面（主题、单位）都用
/// `AnimatedBuilder` 监听。所有写入都是「先改内存、通知、再异步落盘」，
/// 保证 UI 立即响应，落盘失败也只是下次启动回退默认值。
class SettingsService extends ChangeNotifier {
  SettingsService({SharedPreferences? preferences}) : _prefs = preferences;

  // 存储键统一加前缀，避免和未来其它模块冲突。
  static const _kSpeedUnit = 'settings.speed_unit';
  static const _kDistanceUnit = 'settings.distance_unit';
  static const _kCalibrationSeconds = 'settings.calibration_seconds';
  static const _kGpsAccuracyLimit = 'settings.gps_accuracy_limit';
  static const _kDefaultScreenAwake = 'settings.default_screen_awake';
  static const _kConfirmBeforeStop = 'settings.confirm_before_stop';
  static const _kAccelTargetSpeed = 'settings.accel_target_speed_kmh';
  static const _kAccelRollout = 'settings.accel_rollout';
  static const _kAccelCountdown = 'settings.accel_countdown_seconds';
  static const _kAccelRecordTrack = 'settings.accel_record_track';
  static const _kShowLiveTrack = 'settings.show_live_track';
  static const _kMapStyle = 'settings.map_style';

  SharedPreferences? _prefs;
  bool _loaded = false;

  SpeedUnit _speedUnit = SpeedUnit.kmh;
  DistanceUnit _distanceUnit = DistanceUnit.km;
  int _calibrationSeconds = 3;
  double _gpsAccuracyLimit = 35;
  bool _defaultScreenAwake = false;
  bool _confirmBeforeStop = true;
  double _accelTargetSpeedKmh = 100;
  bool _accelRollout = false;
  int _accelCountdownSeconds = 3;
  bool _accelRecordTrack = true;
  bool _showLiveTrack = true;
  MapStyle _mapStyle = MapStyle.satellite;

  bool get loaded => _loaded;

  SpeedUnit get speedUnit => _speedUnit;
  DistanceUnit get distanceUnit => _distanceUnit;

  /// 海拔单位跟随距离单位：英制用英尺，公制用米。
  ElevationUnit get elevationUnit =>
      _distanceUnit == DistanceUnit.mi ? ElevationUnit.ft : ElevationUnit.m;

  int get calibrationSeconds => _calibrationSeconds;
  double get gpsAccuracyLimit => _gpsAccuracyLimit;
  bool get defaultScreenAwake => _defaultScreenAwake;
  bool get confirmBeforeStop => _confirmBeforeStop;
  double get accelTargetSpeedKmh => _accelTargetSpeedKmh;
  bool get accelRollout => _accelRollout;
  int get accelCountdownSeconds => _accelCountdownSeconds;
  bool get accelRecordTrack => _accelRecordTrack;
  bool get showLiveTrack => _showLiveTrack;
  MapStyle get mapStyle => _mapStyle;

  Future<void> load() async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
      final prefs = _prefs!;
      _speedUnit = SpeedUnit.fromName(prefs.getString(_kSpeedUnit));
      _distanceUnit = DistanceUnit.fromName(prefs.getString(_kDistanceUnit));
      _calibrationSeconds =
          _allowedCalibration(prefs.getInt(_kCalibrationSeconds) ?? 3);
      _gpsAccuracyLimit = (prefs.getDouble(_kGpsAccuracyLimit) ?? 35)
          .clamp(10.0, 50.0)
          .toDouble();
      _defaultScreenAwake = prefs.getBool(_kDefaultScreenAwake) ?? false;
      _confirmBeforeStop = prefs.getBool(_kConfirmBeforeStop) ?? true;
      _accelTargetSpeedKmh =
          _allowedAccelTarget(prefs.getDouble(_kAccelTargetSpeed) ?? 100);
      _accelRollout = prefs.getBool(_kAccelRollout) ?? false;
      _accelCountdownSeconds =
          _allowedCountdown(prefs.getInt(_kAccelCountdown) ?? 3);
      _accelRecordTrack = prefs.getBool(_kAccelRecordTrack) ?? true;
      _showLiveTrack = prefs.getBool(_kShowLiveTrack) ?? true;
      _mapStyle = MapStyle.fromName(prefs.getString(_kMapStyle));
      _loaded = true;
      notifyListeners();
    } catch (_) {
      // 读设置失败不应该阻止应用启动，保持默认值即可。
      _loaded = true;
      notifyListeners();
    }
  }

  Future<void> setSpeedUnit(SpeedUnit value) async {
    if (_speedUnit == value) {
      return;
    }
    _speedUnit = value;
    notifyListeners();
    await _saveString(_kSpeedUnit, value.name);
  }

  Future<void> setDistanceUnit(DistanceUnit value) async {
    if (_distanceUnit == value) {
      return;
    }
    _distanceUnit = value;
    notifyListeners();
    await _saveString(_kDistanceUnit, value.name);
  }

  Future<void> setCalibrationSeconds(int value) async {
    final next = _allowedCalibration(value);
    if (_calibrationSeconds == next) {
      return;
    }
    _calibrationSeconds = next;
    notifyListeners();
    await _saveInt(_kCalibrationSeconds, next);
  }

  Future<void> setGpsAccuracyLimit(double value) async {
    final next = value.clamp(10.0, 50.0).toDouble();
    if (_gpsAccuracyLimit == next) {
      return;
    }
    _gpsAccuracyLimit = next;
    notifyListeners();
    await _saveDouble(_kGpsAccuracyLimit, next);
  }

  Future<void> setDefaultScreenAwake(bool value) async {
    if (_defaultScreenAwake == value) {
      return;
    }
    _defaultScreenAwake = value;
    notifyListeners();
    await _saveBool(_kDefaultScreenAwake, value);
  }

  Future<void> setConfirmBeforeStop(bool value) async {
    if (_confirmBeforeStop == value) {
      return;
    }
    _confirmBeforeStop = value;
    notifyListeners();
    await _saveBool(_kConfirmBeforeStop, value);
  }

  Future<void> setAccelTargetSpeedKmh(double value) async {
    final next = _allowedAccelTarget(value);
    if (_accelTargetSpeedKmh == next) {
      return;
    }
    _accelTargetSpeedKmh = next;
    notifyListeners();
    await _saveDouble(_kAccelTargetSpeed, next);
  }

  Future<void> setAccelRollout(bool value) async {
    if (_accelRollout == value) {
      return;
    }
    _accelRollout = value;
    notifyListeners();
    await _saveBool(_kAccelRollout, value);
  }

  Future<void> setAccelCountdownSeconds(int value) async {
    final next = _allowedCountdown(value);
    if (_accelCountdownSeconds == next) {
      return;
    }
    _accelCountdownSeconds = next;
    notifyListeners();
    await _saveInt(_kAccelCountdown, next);
  }

  Future<void> setAccelRecordTrack(bool value) async {
    if (_accelRecordTrack == value) {
      return;
    }
    _accelRecordTrack = value;
    notifyListeners();
    await _saveBool(_kAccelRecordTrack, value);
  }

  Future<void> setShowLiveTrack(bool value) async {
    if (_showLiveTrack == value) {
      return;
    }
    _showLiveTrack = value;
    notifyListeners();
    await _saveBool(_kShowLiveTrack, value);
  }

  Future<void> setMapStyle(MapStyle value) async {
    if (_mapStyle == value) {
      return;
    }
    _mapStyle = value;
    notifyListeners();
    await _saveString(_kMapStyle, value.name);
  }

  /// 恢复全部默认值（设置页的「恢复默认设置」）。
  Future<void> resetToDefaults() async {
    _speedUnit = SpeedUnit.kmh;
    _distanceUnit = DistanceUnit.km;
    _calibrationSeconds = 3;
    _gpsAccuracyLimit = 35;
    _defaultScreenAwake = false;
    _confirmBeforeStop = true;
    _accelTargetSpeedKmh = 100;
    _accelRollout = false;
    _accelCountdownSeconds = 3;
    _accelRecordTrack = true;
    _showLiveTrack = true;
    _mapStyle = MapStyle.satellite;
    notifyListeners();
    try {
      final prefs = _prefs;
      if (prefs == null) {
        return;
      }
      await prefs.remove(_kSpeedUnit);
      await prefs.remove(_kDistanceUnit);
      await prefs.remove(_kCalibrationSeconds);
      await prefs.remove(_kGpsAccuracyLimit);
      await prefs.remove(_kDefaultScreenAwake);
      await prefs.remove(_kConfirmBeforeStop);
      await prefs.remove(_kAccelTargetSpeed);
      await prefs.remove(_kAccelRollout);
      await prefs.remove(_kAccelCountdown);
      await prefs.remove(_kAccelRecordTrack);
      await prefs.remove(_kShowLiveTrack);
      await prefs.remove(_kMapStyle);
    } catch (_) {
      // 落盘失败不影响本次会话。
    }
  }

  int _allowedCalibration(int value) {
    const allowed = [2, 3, 5];
    return allowed.contains(value) ? value : 3;
  }

  int _allowedCountdown(int value) {
    const allowed = [0, 3];
    return allowed.contains(value) ? value : 3;
  }

  double _allowedAccelTarget(double value) {
    const allowed = [60.0, 100.0, 200.0];
    return allowed.contains(value) ? value : 100.0;
  }

  Future<void> _saveString(String key, String value) async {
    await _guard(() => _prefs?.setString(key, value));
  }

  Future<void> _saveInt(String key, int value) async {
    await _guard(() => _prefs?.setInt(key, value));
  }

  Future<void> _saveDouble(String key, double value) async {
    await _guard(() => _prefs?.setDouble(key, value));
  }

  Future<void> _saveBool(String key, bool value) async {
    await _guard(() => _prefs?.setBool(key, value));
  }

  Future<void> _guard(Future<bool>? Function() write) async {
    try {
      await write();
    } catch (_) {
      // 写入失败时静默处理：内存值已生效，下次启动回退默认值。
    }
  }
}
