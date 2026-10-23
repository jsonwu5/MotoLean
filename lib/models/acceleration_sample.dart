/// 零百测试的原始速度采样点。
class AccelerationSample {
  const AccelerationSample({
    this.id,
    required this.runId,
    required this.tMs,
    required this.speedKmh,
    this.accuracyM,
    this.lat,
    this.lon,
  });

  final int? id;
  final int runId;

  /// 相对测试开始的毫秒数。
  final int tMs;

  final double speedKmh;
  final double? accuracyM;
  final double? lat;
  final double? lon;

  bool get hasPosition => lat != null && lon != null;

  double get speedMps => speedKmh / 3.6;

  Map<String, Object?> toMap() => {
        'run_id': runId,
        't_ms': tMs,
        'speed_kmh': speedKmh,
        'accuracy_m': accuracyM,
        'lat': lat,
        'lon': lon,
      };

  factory AccelerationSample.fromMap(Map<String, Object?> map) =>
      AccelerationSample(
        id: map['id'] as int?,
        runId: (map['run_id'] as num).toInt(),
        tMs: (map['t_ms'] as num).toInt(),
        speedKmh: (map['speed_kmh'] as num).toDouble(),
        accuracyM: (map['accuracy_m'] as num?)?.toDouble(),
        lat: (map['lat'] as num?)?.toDouble(),
        lon: (map['lon'] as num?)?.toDouble(),
      );
}
