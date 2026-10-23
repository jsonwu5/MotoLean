import 'package:flutter_test/flutter_test.dart';
import 'package:motolean/models/ride_sample.dart';
import 'package:motolean/models/ride_session.dart';
import 'package:motolean/services/demo_ride.dart';
import 'package:motolean/services/ride_store.dart';

void main() {
  test('memory store imports, reads and deletes a demo ride', () async {
    final store = RideStore(useMemory: true);
    await store.init();

    final ride = DemoRideGenerator.build(
      startedAt: DateTime(2026, 10, 1, 9, 30),
    );
    final id = await store.importDemoRide(ride);

    final sessions = await store.loadSessions();
    expect(sessions, hasLength(1));
    expect(sessions.single.id, id);
    expect(sessions.single.sampleCount, ride.samples.length);
    expect(sessions.single.isDemo, isTrue);

    final samples = await store.loadSamples(id);
    expect(samples, hasLength(ride.samples.length));
    expect(samples.first.sessionId, id);
    expect(samples.last.tMs, ride.samples.last.tMs);

    expect((await store.loadSession(id))?.isDemo, isTrue);

    await store.deleteSession(id);
    expect(await store.loadSessions(), isEmpty);
    expect(await store.loadSamples(id), isEmpty);
  });

  test('memory store keeps live-updated summaries', () async {
    final store = RideStore(useMemory: true);
    await store.init();
    final startedAt = DateTime(2026, 10, 2, 8);
    final id = await store.createSession(RideSession(startedAt: startedAt));

    await store.insertSample(
      RideSample(
        sessionId: id,
        tMs: 1000,
        leanDeg: 22,
        lat: 30.47,
        lon: 119.63,
        speedMps: 12,
      ),
    );
    await store.updateSession(
      RideSession(
        id: id,
        startedAt: startedAt,
        endedAt: startedAt.add(const Duration(seconds: 1)),
        distanceM: 12,
        durationS: 1,
        movingS: 1,
        maxSpeedMps: 12,
        avgSpeedMps: 12,
        maxLeanRightDeg: 22,
        sampleCount: 1,
      ),
    );

    final session = await store.loadSession(id);
    expect(session, isNotNull);
    expect(session!.distanceM, 12);
    expect(session.maxLeanRightDeg, 22);
    expect(await store.loadSamples(id), hasLength(1));
  });
}
