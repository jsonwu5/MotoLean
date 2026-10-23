import 'package:flutter_test/flutter_test.dart';
import 'package:motolean/models/ride_sample.dart';
import 'package:motolean/models/ride_session.dart';
import 'package:motolean/services/ride_exporter.dart';

void main() {
  final startedAt = DateTime.utc(2026, 10, 1, 2, 3, 4);
  final session = RideSession(
    id: 1,
    startedAt: startedAt,
    endedAt: startedAt.add(const Duration(minutes: 2)),
    distanceM: 1500,
    durationS: 120,
    movingS: 100,
    maxSpeedMps: 20,
    avgSpeedMps: 15,
    maxLeanLeftDeg: 28,
    maxLeanRightDeg: 41,
    elevationGainM: 32,
    sampleCount: 4,
  );
  final samples = [
    RideSample(
      sessionId: 1,
      tMs: 0,
      leanDeg: -12.5,
      lat: 30.47,
      lon: 119.63,
      altitudeM: 310.2,
      speedMps: 11.1,
      accuracyM: 4.0,
    ),
    RideSample(
      sessionId: 1,
      tMs: 1000,
      leanDeg: 35.2,
      lat: 30.4701,
      lon: 119.6302,
      altitudeM: 312.0,
      speedMps: 16.7,
      accuracyM: 3.5,
    ),
    const RideSample(
      sessionId: 1,
      tMs: 55000,
      leanDeg: 0,
    ),
    RideSample(
      sessionId: 1,
      tMs: 88000,
      leanDeg: 8.1,
      lat: 30.472,
      lon: 119.634,
      altitudeM: 330,
      speedMps: 14,
      accuracyM: 5,
    ),
  ];

  group('CSV export', () {
    final csv = RideExporter.buildCsv(session, samples);

    test('starts with a UTF-8 BOM and header', () {
      expect(csv.startsWith('\uFEFFtime,'), isTrue);
      expect(csv, contains('lean_deg'));
    });

    test('writes every sample and formats values', () {
      final lines = csv.trim().split('\n');
      expect(lines.length, 5); // BOM + header + 4 samples
      expect(csv, contains('2026-10-01T02:03:04.000Z'));
      expect(csv, contains('-12.5'));
      expect(csv, contains('35.2'));
      expect(csv, contains('30.4700000'));
    });

    test('leaves GPS fields empty when missing', () {
      expect(csv, contains(',55,,,'));
    });
  });

  group('GPX export', () {
    final gpx = RideExporter.buildGpx(session, samples);

    test('is a GPX 1.1 document with a track', () {
      expect(gpx.startsWith('<?xml version="1.0"'), isTrue);
      expect(gpx, contains('version="1.1"'));
      expect(gpx, contains('<trk>'));
      expect(gpx, contains('lat="30.4700000"'));
      expect(gpx, contains('lon="119.6300000"'));
    });

    test('splits segments across long GPS gaps', () {
      expect('<trkseg>'.allMatches(gpx).length, 2);
    });

    test('includes speed and lean extensions', () {
      expect(gpx, contains('<ml:speed_kmh>40.0</ml:speed_kmh>'));
      expect(gpx, contains('<ml:lean_deg>-12.5</ml:lean_deg>'));
      expect(gpx, contains('<ml:lean_deg>35.2</ml:lean_deg>'));
    });

    test('produces valid empty track when no sample has a position', () {
      final empty = RideExporter.buildGpx(
        session,
        const [
          RideSample(sessionId: 1, tMs: 0, leanDeg: 0),
        ],
      );
      expect(empty, contains('</trk>'));
      expect(empty, isNot(contains('<trkseg>')));
    });
  });
}
