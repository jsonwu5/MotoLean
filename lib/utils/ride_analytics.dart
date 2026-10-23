import '../models/ride_sample.dart';

class LeanBandStat {
  const LeanBandStat({
    required this.label,
    required this.lowerDeg,
    required this.upperDeg,
    required this.seconds,
    required this.fraction,
  });

  final String label;
  final double lowerDeg;
  final double upperDeg;
  final int seconds;
  final double fraction;
}

class SpeedPoint {
  const SpeedPoint(this.tSeconds, this.speedKmh);

  final double tSeconds;
  final double speedKmh;
}

class RideAnalytics {
  static const List<(double, double, String)> _bands = [
    (0, 10, '0–10°'),
    (10, 20, '10–20°'),
    (20, 30, '20–30°'),
    (30, 40, '30–40°'),
    (40, 90, '40°+'),
  ];

  /// Time spent in each lean band. Samples are recorded at 1 Hz, so each
  /// sample represents roughly one second.
  static List<LeanBandStat> leanBands(List<RideSample> samples) {
    final counts = List<int>.filled(_bands.length, 0);
    for (final sample in samples) {
      final lean = sample.leanDeg.abs();
      for (var i = 0; i < _bands.length; i++) {
        if (lean >= _bands[i].$1 && lean < _bands[i].$2) {
          counts[i]++;
          break;
        }
      }
    }
    final total = samples.isEmpty ? 1 : samples.length;
    return [
      for (var i = 0; i < _bands.length; i++)
        LeanBandStat(
          label: _bands[i].$3,
          lowerDeg: _bands[i].$1,
          upperDeg: _bands[i].$2,
          seconds: counts[i],
          fraction: counts[i] / total,
        ),
    ];
  }

  static int secondsAboveLean(List<RideSample> samples, double threshold) {
    var count = 0;
    for (final sample in samples) {
      if (sample.leanDeg.abs() >= threshold) {
        count++;
      }
    }
    return count;
  }

  /// Counts distinct corners using a simple hysteresis threshold.
  static int cornerCount(List<RideSample> samples, {double threshold = 15}) {
    var corners = 0;
    var inCorner = false;
    for (final sample in samples) {
      final lean = sample.leanDeg.abs();
      if (!inCorner && lean >= threshold) {
        corners++;
        inCorner = true;
      } else if (inCorner && lean < threshold * 0.6) {
        inCorner = false;
      }
    }
    return corners;
  }

  /// Speed series, downsampled so charts stay light on long rides.
  static List<SpeedPoint> speedSeries(
    List<RideSample> samples, {
    int maxPoints = 300,
  }) {
    final points = <SpeedPoint>[];
    for (final sample in samples) {
      final speed = sample.speedKmh;
      if (speed == null) {
        continue;
      }
      points.add(SpeedPoint(sample.tMs / 1000.0, speed));
    }
    if (points.length <= maxPoints) {
      return points;
    }
    final step = points.length / maxPoints;
    return [
      for (var i = 0; i < maxPoints; i++) points[(i * step).floor()],
    ];
  }

  static double maxLeanLeft(List<RideSample> samples) {
    var maxLean = 0.0;
    for (final sample in samples) {
      if (sample.leanDeg < 0) {
        maxLean = maxLean > -sample.leanDeg ? maxLean : -sample.leanDeg;
      }
    }
    return maxLean;
  }

  static double maxLeanRight(List<RideSample> samples) {
    var maxLean = 0.0;
    for (final sample in samples) {
      if (sample.leanDeg > maxLean) {
        maxLean = sample.leanDeg;
      }
    }
    return maxLean;
  }
}
