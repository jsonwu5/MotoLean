/// Summary of a completed or in-progress ride.
class RideSession {
  const RideSession({
    this.id,
    required this.startedAt,
    this.endedAt,
    this.distanceM = 0,
    this.durationS = 0,
    this.movingS = 0,
    this.maxSpeedMps = 0,
    this.avgSpeedMps = 0,
    this.maxLeanLeftDeg = 0,
    this.maxLeanRightDeg = 0,
    this.elevationGainM = 0,
    this.sampleCount = 0,
    this.isDemo = false,
    this.note,
  });

  final int? id;
  final DateTime startedAt;
  final DateTime? endedAt;
  final double distanceM;
  final int durationS;
  final int movingS;
  final double maxSpeedMps;
  final double avgSpeedMps;

  /// Magnitudes, always non-negative.
  final double maxLeanLeftDeg;
  final double maxLeanRightDeg;
  final double elevationGainM;
  final int sampleCount;
  final bool isDemo;
  final String? note;

  bool get isFinished => endedAt != null;

  double get distanceKm => distanceM / 1000;
  double get maxSpeedKmh => maxSpeedMps * 3.6;
  double get avgSpeedKmh => avgSpeedMps * 3.6;

  RideSession copyWith({
    int? id,
    DateTime? startedAt,
    DateTime? endedAt,
    double? distanceM,
    int? durationS,
    int? movingS,
    double? maxSpeedMps,
    double? avgSpeedMps,
    double? maxLeanLeftDeg,
    double? maxLeanRightDeg,
    double? elevationGainM,
    int? sampleCount,
    bool? isDemo,
    String? note,
  }) =>
      RideSession(
        id: id ?? this.id,
        startedAt: startedAt ?? this.startedAt,
        endedAt: endedAt ?? this.endedAt,
        distanceM: distanceM ?? this.distanceM,
        durationS: durationS ?? this.durationS,
        movingS: movingS ?? this.movingS,
        maxSpeedMps: maxSpeedMps ?? this.maxSpeedMps,
        avgSpeedMps: avgSpeedMps ?? this.avgSpeedMps,
        maxLeanLeftDeg: maxLeanLeftDeg ?? this.maxLeanLeftDeg,
        maxLeanRightDeg: maxLeanRightDeg ?? this.maxLeanRightDeg,
        elevationGainM: elevationGainM ?? this.elevationGainM,
        sampleCount: sampleCount ?? this.sampleCount,
        isDemo: isDemo ?? this.isDemo,
        note: note ?? this.note,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'started_at': startedAt.millisecondsSinceEpoch,
        'ended_at': endedAt?.millisecondsSinceEpoch,
        'distance_m': distanceM,
        'duration_s': durationS,
        'moving_s': movingS,
        'max_speed_mps': maxSpeedMps,
        'avg_speed_mps': avgSpeedMps,
        'max_lean_left_deg': maxLeanLeftDeg,
        'max_lean_right_deg': maxLeanRightDeg,
        'elevation_gain_m': elevationGainM,
        'sample_count': sampleCount,
        'is_demo': isDemo ? 1 : 0,
        'note': note,
      };

  factory RideSession.fromMap(Map<String, Object?> map) => RideSession(
        id: map['id'] as int?,
        startedAt:
            DateTime.fromMillisecondsSinceEpoch(map['started_at'] as int),
        endedAt: map['ended_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(map['ended_at'] as int),
        distanceM: (map['distance_m'] as num? ?? 0).toDouble(),
        durationS: (map['duration_s'] as num? ?? 0).toInt(),
        movingS: (map['moving_s'] as num? ?? 0).toInt(),
        maxSpeedMps: (map['max_speed_mps'] as num? ?? 0).toDouble(),
        avgSpeedMps: (map['avg_speed_mps'] as num? ?? 0).toDouble(),
        maxLeanLeftDeg: (map['max_lean_left_deg'] as num? ?? 0).toDouble(),
        maxLeanRightDeg: (map['max_lean_right_deg'] as num? ?? 0).toDouble(),
        elevationGainM: (map['elevation_gain_m'] as num? ?? 0).toDouble(),
        sampleCount: (map['sample_count'] as num? ?? 0).toInt(),
        isDemo: (map['is_demo'] as int? ?? 0) == 1,
        note: map['note'] as String?,
      );
}
