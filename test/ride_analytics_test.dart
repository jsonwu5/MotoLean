import 'package:flutter_test/flutter_test.dart';
import 'package:motolean/models/ride_sample.dart';
import 'package:motolean/utils/ride_analytics.dart';

RideSample sample(int second, double lean, {double? speed}) => RideSample(
      sessionId: 1,
      tMs: second * 1000,
      leanDeg: lean,
      speedMps: speed,
    );

void main() {
  group('lean bands', () {
    final samples = [
      sample(0, 0),
      sample(1, 5),
      sample(2, 15),
      sample(3, 25),
      sample(4, 35),
      sample(5, 45),
      sample(6, -15),
    ];

    test('counts samples per band', () {
      final bands = RideAnalytics.leanBands(samples);
      expect(bands.map((b) => b.seconds).toList(), [2, 2, 1, 1, 1]);
      expect(bands.first.fraction, closeTo(2 / 7, 1e-9));
    });

    test('sums to the sample count', () {
      final total = RideAnalytics.leanBands(samples)
          .fold<int>(0, (sum, band) => sum + band.seconds);
      expect(total, samples.length);
    });
  });

  test('max lean uses magnitudes in both directions', () {
    final samples = [sample(0, -42), sample(1, 31), sample(2, 2)];
    expect(RideAnalytics.maxLeanLeft(samples), 42);
    expect(RideAnalytics.maxLeanRight(samples), 31);
  });

  test('corner count uses hysteresis', () {
    final samples = [
      sample(0, 0),
      sample(1, 18),
      sample(2, 20),
      sample(3, 5),
      sample(4, 6),
      sample(5, 22),
      sample(6, 3),
    ];
    expect(RideAnalytics.cornerCount(samples), 2);
  });

  test('seconds above threshold', () {
    final samples = [sample(0, 10), sample(1, 31), sample(2, -35), sample(3, 5)];
    expect(RideAnalytics.secondsAboveLean(samples, 30), 2);
  });

  test('speed series drops samples without GPS speed', () {
    final samples = [
      sample(0, 0, speed: 10),
      sample(1, 0),
      sample(2, 0, speed: 15),
    ];
    final points = RideAnalytics.speedSeries(samples);
    expect(points.length, 2);
    expect(points.last.speedKmh, closeTo(54, 1e-9));
  });

  test('speed series downsamples long rides', () {
    final samples = [
      for (var i = 0; i < 1000; i++) sample(i, 0, speed: 10),
    ];
    expect(RideAnalytics.speedSeries(samples, maxPoints: 100).length, 100);
  });
}
