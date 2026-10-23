/// 单位换算与展示。
///
/// 约定：**内部一律使用 SI 单位**（米、米/秒），只在展示层换算。
/// 这样单位设置随时可切换，已入库的数据不需要迁移。
library;

const double _metersPerMile = 1609.344;
const double _metersPerFoot = 0.3048;
const double _mpsToKmh = 3.6;
const double _mpsToMph = 2.2369362920544;

/// 速度单位。
enum SpeedUnit {
  kmh('km/h'),
  mph('mph');

  const SpeedUnit(this.label);

  /// 展示用单位符号。
  final String label;

  double fromMps(double mps) =>
      this == SpeedUnit.kmh ? mps * _mpsToKmh : mps * _mpsToMph;

  double toMps(double value) =>
      this == SpeedUnit.kmh ? value / _mpsToKmh : value / _mpsToMph;

  static SpeedUnit fromName(String? name) {
    for (final unit in SpeedUnit.values) {
      if (unit.name == name) {
        return unit;
      }
    }
    return SpeedUnit.kmh;
  }
}

/// 距离单位。
enum DistanceUnit {
  km('km', 1000),
  mi('mi', _metersPerMile);

  const DistanceUnit(this.label, this.metersPerUnit);

  final String label;
  final double metersPerUnit;

  double fromMeters(double meters) => meters / metersPerUnit;

  double toMeters(double value) => value * metersPerUnit;

  static DistanceUnit fromName(String? name) {
    for (final unit in DistanceUnit.values) {
      if (unit.name == name) {
        return unit;
      }
    }
    return DistanceUnit.km;
  }
}

/// 海拔/爬升：公制米、英制英尺。
enum ElevationUnit {
  m('m', 1),
  ft('ft', 1 / _metersPerFoot);

  const ElevationUnit(this.label, this.perMeter);

  final String label;
  final double perMeter;

  double fromMeters(double meters) => meters * perMeter;

  double toMeters(double value) => value / perMeter;

  static ElevationUnit fromName(String? name) {
    for (final unit in ElevationUnit.values) {
      if (unit.name == name) {
        return unit;
      }
    }
    return ElevationUnit.m;
  }
}

/// 速度数值（不带单位）。
String formatSpeedValue(double mps, SpeedUnit unit, {int decimals = 0}) {
  final value = unit.fromMps(mps).clamp(0.0, 400.0).toDouble();
  return value.toStringAsFixed(decimals);
}

/// 速度数值 + 单位，例如 `52 km/h`。
String formatSpeedWithUnit(double mps, SpeedUnit unit, {int decimals = 0}) =>
    '${formatSpeedValue(mps, unit, decimals: decimals)} ${unit.label}';

/// 距离数值（自动在千米与米之间切换）。
String formatDistanceValue(double meters, DistanceUnit unit) {
  if (meters < 0) {
    return '0';
  }
  if (unit == DistanceUnit.km) {
    if (meters < 1000) {
      return meters.round().toString();
    }
    return (meters / 1000).toStringAsFixed(1);
  }
  final miles = meters / _metersPerMile;
  if (meters < 320) {
    return (meters / _metersPerFoot).round().toString();
  }
  return miles.toStringAsFixed(miles >= 10 ? 1 : 2);
}

/// 距离的主单位（小距离时公制用米、英制用英尺）。
String distanceValueLabel(double meters, DistanceUnit unit) {
  if (unit == DistanceUnit.km) {
    return meters < 1000 ? 'm' : 'km';
  }
  if (meters < 320) {
    return 'ft';
  }
  return 'mi';
}

/// 距离数值 + 单位，例如 `23.4 km`。
String formatDistanceWithUnit(double meters, DistanceUnit unit) =>
    '${formatDistanceValue(meters, unit)} ${distanceValueLabel(meters, unit)}';

/// 爬升/海拔数值，公制米、英制英尺。
String formatElevationWithUnit(double meters, ElevationUnit unit) {
  final value = unit.fromMeters(meters);
  return '${value.round()} ${unit.label}';
}

/// 速度换算成指定单位的数值（用于图表与阈值比较）。
double speedIn(double mps, SpeedUnit unit) => unit.fromMps(mps);

/// 指定单位下的速度阈值换算回 m/s。
double speedMpsOf(double value, SpeedUnit unit) => unit.toMps(value);
