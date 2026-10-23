/// 一次零百加速测试的结果。
///
/// 时间统一存毫秒；速度内部以 km/h 存储（成绩口径本身就是「到多少 km/h」），
/// 展示时再按用户单位换算。
class AccelerationRun {
  const AccelerationRun({
    this.id,
    required this.startedAt,
    required this.targetSpeedKmh,
    required this.resultMs,
    this.rollout = false,
    this.result60Ms,
    this.result130Ms,
    this.result200Ms,
    this.distanceM,
    this.maxSpeedKmh,
    this.gradePercent,
    this.gpsAccuracyM,
    this.startLat,
    this.startLon,
    this.valid = true,
    this.invalidReason,
    this.isDemo = false,
    this.note,
  });

  final int? id;
  final DateTime startedAt;

  /// 主目标速度，通常是 100 km/h。
  final double targetSpeedKmh;

  /// 原始成绩（0 → 目标速度），毫秒。
  final int resultMs;

  /// 是否包含 1 英尺 rollout（车移动约 30 cm 后才开始计时）。
  final bool rollout;

  final int? result60Ms;
  final int? result130Ms;
  final int? result200Ms;

  /// 起步到达速的距离。
  final double? distanceM;
  final double? maxSpeedKmh;

  /// 平均坡度百分比，上坡为正。
  final double? gradePercent;

  /// 全程 GPS 精度中位数。
  final double? gpsAccuracyM;

  final double? startLat;
  final double? startLon;

  /// 数据是否足以采信（速度回落、空洞、没停稳等会被标记为 false）。
  final bool valid;
  final String? invalidReason;

  final bool isDemo;
  final String? note;

  double get resultSeconds => resultMs / 1000;

  double? get result60Seconds => result60Ms == null ? null : result60Ms! / 1000;

  double? get result130Seconds =>
      result130Ms == null ? null : result130Ms! / 1000;

  double? get result200Seconds =>
      result200Ms == null ? null : result200Ms! / 1000;

  AccelerationRun copyWith({
    int? id,
    DateTime? startedAt,
    double? targetSpeedKmh,
    int? resultMs,
    bool? rollout,
    int? result60Ms,
    int? result130Ms,
    int? result200Ms,
    double? distanceM,
    double? maxSpeedKmh,
    double? gradePercent,
    double? gpsAccuracyM,
    double? startLat,
    double? startLon,
    bool? valid,
    String? invalidReason,
    bool? isDemo,
    String? note,
  }) =>
      AccelerationRun(
        id: id ?? this.id,
        startedAt: startedAt ?? this.startedAt,
        targetSpeedKmh: targetSpeedKmh ?? this.targetSpeedKmh,
        resultMs: resultMs ?? this.resultMs,
        rollout: rollout ?? this.rollout,
        result60Ms: result60Ms ?? this.result60Ms,
        result130Ms: result130Ms ?? this.result130Ms,
        result200Ms: result200Ms ?? this.result200Ms,
        distanceM: distanceM ?? this.distanceM,
        maxSpeedKmh: maxSpeedKmh ?? this.maxSpeedKmh,
        gradePercent: gradePercent ?? this.gradePercent,
        gpsAccuracyM: gpsAccuracyM ?? this.gpsAccuracyM,
        startLat: startLat ?? this.startLat,
        startLon: startLon ?? this.startLon,
        valid: valid ?? this.valid,
        invalidReason: invalidReason ?? this.invalidReason,
        isDemo: isDemo ?? this.isDemo,
        note: note ?? this.note,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'started_at': startedAt.millisecondsSinceEpoch,
        'target_speed_kmh': targetSpeedKmh,
        'result_ms': resultMs,
        'rollout': rollout ? 1 : 0,
        'result_60_ms': result60Ms,
        'result_130_ms': result130Ms,
        'result_200_ms': result200Ms,
        'distance_m': distanceM,
        'max_speed_kmh': maxSpeedKmh,
        'grade_percent': gradePercent,
        'gps_accuracy_m': gpsAccuracyM,
        'start_lat': startLat,
        'start_lon': startLon,
        'valid': valid ? 1 : 0,
        'invalid_reason': invalidReason,
        'is_demo': isDemo ? 1 : 0,
        'note': note,
      };

  factory AccelerationRun.fromMap(Map<String, Object?> map) => AccelerationRun(
        id: map['id'] as int?,
        startedAt:
            DateTime.fromMillisecondsSinceEpoch(map['started_at'] as int),
        targetSpeedKmh: (map['target_speed_kmh'] as num).toDouble(),
        resultMs: (map['result_ms'] as num).toInt(),
        rollout: (map['rollout'] as int? ?? 0) == 1,
        result60Ms: (map['result_60_ms'] as num?)?.toInt(),
        result130Ms: (map['result_130_ms'] as num?)?.toInt(),
        result200Ms: (map['result_200_ms'] as num?)?.toInt(),
        distanceM: (map['distance_m'] as num?)?.toDouble(),
        maxSpeedKmh: (map['max_speed_kmh'] as num?)?.toDouble(),
        gradePercent: (map['grade_percent'] as num?)?.toDouble(),
        gpsAccuracyM: (map['gps_accuracy_m'] as num?)?.toDouble(),
        startLat: (map['start_lat'] as num?)?.toDouble(),
        startLon: (map['start_lon'] as num?)?.toDouble(),
        valid: (map['valid'] as int? ?? 1) == 1,
        invalidReason: map['invalid_reason'] as String?,
        isDemo: (map['is_demo'] as int? ?? 0) == 1,
        note: map['note'] as String?,
      );
}
