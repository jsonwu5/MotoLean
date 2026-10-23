/// One recorded second of a ride.
class RideSample {
  const RideSample({
    this.id,
    required this.sessionId,
    required this.tMs,
    required this.leanDeg,
    this.lat,
    this.lon,
    this.altitudeM,
    this.speedMps,
    this.accuracyM,
  });

  final int? id;
  final int sessionId;

  /// Milliseconds since the session started.
  final int tMs;
  final double leanDeg;
  final double? lat;
  final double? lon;
  final double? altitudeM;
  final double? speedMps;
  final double? accuracyM;

  bool get hasPosition => lat != null && lon != null;

  double? get speedKmh =>
      speedMps == null ? null : (speedMps! * 3.6).clamp(0, 400).toDouble();

  Map<String, Object?> toMap() => {
        'session_id': sessionId,
        't_ms': tMs,
        'lean_deg': leanDeg,
        'lat': lat,
        'lon': lon,
        'alt_m': altitudeM,
        'speed_mps': speedMps,
        'accuracy_m': accuracyM,
      };

  factory RideSample.fromMap(Map<String, Object?> map) => RideSample(
        id: map['id'] as int?,
        sessionId: map['session_id'] as int,
        tMs: map['t_ms'] as int,
        leanDeg: (map['lean_deg'] as num).toDouble(),
        lat: (map['lat'] as num?)?.toDouble(),
        lon: (map['lon'] as num?)?.toDouble(),
        altitudeM: (map['alt_m'] as num?)?.toDouble(),
        speedMps: (map['speed_mps'] as num?)?.toDouble(),
        accuracyM: (map['accuracy_m'] as num?)?.toDouble(),
      );
}
