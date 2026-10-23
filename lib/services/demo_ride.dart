import 'dart:math' as math;

import '../models/ride_sample.dart';
import '../models/ride_session.dart';

/// Generates a realistic-looking synthetic ride so the app can be explored
/// without riding. It is clearly marked as demo data everywhere in the UI.
///
/// Each corner is defined by a peak lean angle and a total heading change.
/// The lean angle and current speed give the curvature, and integrating the
/// heading produces a winding mountain road whose turns match the recorded
/// lean data.
class DemoRideGenerator {
  static const _originLat = 30.4700;
  static const _originLon = 119.6300;

  static RideSession generateSession({DateTime? startedAt}) =>
      build(startedAt: startedAt).session;

  static DemoRide build({DateTime? startedAt}) {
    final start =
        startedAt ?? DateTime.now().subtract(const Duration(minutes: 27));
    const durationS = 1620;
    const g = 9.81;
    const degreesToRadians = math.pi / 180;

    final samples = <RideSample>[];
    var lat = _originLat;
    var lon = _originLon;
    var heading = 0.0; // radians, 0 = north, positive = clockwise
    var distance = 0.0;
    var movingS = 0;
    var maxSpeed = 0.0;
    var maxLeanLeft = 0.0;
    var maxLeanRight = 0.0;
    var elevationGain = 0.0;
    double? previousAltitude;
    var speedKmh = 52.0;
    var smoothedLean = 0.0;

    var cornerIndex = 2; // start with a real corner, not a straight
    var inCorner = true;
    var cornerPhase = 0.0;
    var cornerDuration = 6.0;
    var cornerKappaSign = 1.0;
    var cornerPeakLeanDeg = 40.0;
    var straightRemaining = 0.0;

    void startCorner(double speedMps) {
      final sign = cornerIndex.isEven ? 1.0 : -1.0;
      final peakLean = 26 + cornerIndex * 7 % 22; // 26..47 degrees
      final headingChange = 0.7 + (cornerIndex * 5 % 12) * 0.1; // 0.7..1.8 rad
      final kappaAtStart = math.tan(peakLean * degreesToRadians) *
          g /
          (speedMps * speedMps);
      final meanKappa = 2 * kappaAtStart / math.pi;
      final duration = headingChange / (speedMps * meanKappa);
      cornerPeakLeanDeg = peakLean.toDouble();
      cornerKappaSign = sign;
      cornerDuration = duration.clamp(4.0, 18.0).toDouble();
      cornerPhase = 0;
      inCorner = true;
    }

    startCorner(speedKmh / 3.6);

    for (var t = 0; t <= durationS; t++) {
      final leanTarget = inCorner
          ? cornerKappaSign *
              cornerPeakLeanDeg *
              math.sin(math.pi * cornerPhase.clamp(0.0, 1.0))
          : 0.0;

      // Flowing mountain-road speed: rolling undulation, two slower sections,
      // and a little extra caution in corners.
      final baseSpeed = 55 +
          13 * math.sin(t * 0.011) +
          8 * math.sin(t * 0.043 + 1.4) -
          14 * math.exp(-math.pow((t - 980) / 70, 2)) -
          12 * math.exp(-math.pow((t - 420) / 55, 2)) -
          (inCorner ? 6 * cornerPeakLeanDeg / 47 : 0.0);
      speedKmh += (baseSpeed - speedKmh) * 0.08;
      final speedMps = (speedKmh / 3.6).clamp(8.0, 92 / 3.6).toDouble();
      final stepMeters = t == 0 ? 0.0 : speedMps;

      if (t > 0) {
        distance += stepMeters;
        if (speedMps > 2.5) {
          movingS++;
        }
        maxSpeed = math.max(maxSpeed, speedMps);
      }

      // Curvature follows from the target lean and the current speed, so the
      // recorded lean and the generated road stay physically consistent.
      final curvature = math.tan(leanTarget * degreesToRadians) *
          g /
          (speedMps * speedMps);
      final measuredLean =
          leanTarget + 0.45 * math.sin(t * 1.7) + 0.2 * math.sin(t * 3.1);
      smoothedLean += (measuredLean - smoothedLean) * 0.8;

      if (smoothedLean < -5) {
        maxLeanLeft = math.max(maxLeanLeft, -smoothedLean);
      }
      if (smoothedLean > 5) {
        maxLeanRight = math.max(maxLeanRight, smoothedLean);
      }

      heading += curvature * stepMeters;
      if (t > 0) {
        lat += math.cos(heading) * stepMeters / 111320.0;
        lon += math.sin(heading) *
            stepMeters /
            (111320.0 * math.cos(lat * degreesToRadians));
      }

      final altitude = 315 +
          260 * math.sin(distance / 6000) +
          60 * math.sin(distance / 2600 + 0.7);
      if (previousAltitude != null) {
        final delta = altitude - previousAltitude;
        if (delta > 0.2) {
          elevationGain += delta;
        }
      }
      previousAltitude = altitude;

      samples.add(
        RideSample(
          sessionId: 0,
          tMs: t * 1000,
          leanDeg: double.parse(smoothedLean.toStringAsFixed(2)),
          lat: lat,
          lon: lon,
          altitudeM: double.parse(altitude.toStringAsFixed(1)),
          speedMps: double.parse(speedMps.toStringAsFixed(3)),
          accuracyM: 3.5,
        ),
      );

      if (t > 0) {
        if (inCorner) {
          cornerPhase += 1 / cornerDuration;
          if (cornerPhase >= 1) {
            inCorner = false;
            cornerPhase = 0;
            cornerIndex++;
            straightRemaining = (4 + cornerIndex * 3 % 7).toDouble();
          }
        } else {
          straightRemaining -= 1;
          if (straightRemaining <= 0) {
            startCorner(speedMps);
          }
        }
      }
    }

    final session = RideSession(
      startedAt: start,
      endedAt: start.add(const Duration(seconds: durationS)),
      distanceM: distance,
      durationS: durationS,
      movingS: movingS,
      maxSpeedMps: maxSpeed,
      avgSpeedMps: movingS == 0 ? 0.0 : distance / movingS,
      maxLeanLeftDeg: maxLeanLeft,
      maxLeanRightDeg: maxLeanRight,
      elevationGainM: elevationGain,
      sampleCount: samples.length,
      isDemo: true,
      note: '演示数据 · 模拟山路，非真实轨迹',
    );

    return DemoRide(session: session, samples: samples);
  }
}

class DemoRide {
  const DemoRide({required this.session, required this.samples});

  final RideSession session;
  final List<RideSample> samples;
}
