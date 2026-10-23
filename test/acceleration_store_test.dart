import 'package:flutter_test/flutter_test.dart';
import 'package:motolean/models/acceleration_run.dart';
import 'package:motolean/models/acceleration_sample.dart';
import 'package:motolean/services/ride_store.dart';

AccelerationRun _run({
  DateTime? startedAt,
  int resultMs = 4820,
  bool valid = true,
}) =>
    AccelerationRun(
      startedAt: startedAt ?? DateTime(2026, 10, 23, 10, 30),
      targetSpeedKmh: 100,
      resultMs: resultMs,
      result60Ms: 2100,
      result130Ms: 3400,
      distanceM: 68.5,
      maxSpeedKmh: 108,
      gradePercent: 1.2,
      gpsAccuracyM: 6,
      startLat: 30.47,
      startLon: 119.63,
      valid: valid,
      invalidReason: valid ? null : '检测到速度回落',
    );

List<AccelerationSample> _samples(int runId) => [
      AccelerationSample(runId: runId, tMs: 0, speedKmh: 0, accuracyM: 6),
      AccelerationSample(runId: runId, tMs: 1000, speedKmh: 22, accuracyM: 6),
      AccelerationSample(runId: runId, tMs: 2000, speedKmh: 48, accuracyM: 6),
      AccelerationSample(runId: runId, tMs: 3000, speedKmh: 72, accuracyM: 6),
    ];

void main() {
  test('内存 store 保存、读取、删除零百成绩', () async {
    final store = RideStore(useMemory: true);
    final id = await store.createAccelerationRun(_run());

    expect(id, greaterThan(0));
    await store.insertAccelerationSamples(id, _samples(id));

    final loaded = await store.loadAccelerationRun(id);
    expect(loaded, isNotNull);
    expect(loaded!.resultMs, 4820);
    expect(loaded.rollout, isFalse);
    expect(loaded.valid, isTrue);
    expect(loaded.resultSeconds, closeTo(4.82, 0.001));

    final samples = await store.loadAccelerationSamples(id);
    expect(samples.length, 4);
    // 采样点按时间升序返回。
    expect(samples.first.tMs, 0);
    expect(samples.last.tMs, 3000);
    // 传入的 runId 会被实际 id 覆盖。
    expect(samples.every((sample) => sample.runId == id), isTrue);

    await store.deleteAccelerationRun(id);
    expect(await store.loadAccelerationRun(id), isNull);
    expect(await store.loadAccelerationSamples(id), isEmpty);
  });

  test('成绩列表按开始时间倒序', () async {
    final store = RideStore(useMemory: true);
    final older = await store.createAccelerationRun(
      _run(startedAt: DateTime(2026, 10, 1)),
    );
    final newer = await store.createAccelerationRun(
      _run(startedAt: DateTime(2026, 10, 20)),
    );

    final runs = await store.loadAccelerationRuns();
    expect(runs.length, 2);
    expect(runs.first.id, newer);
    expect(runs.last.id, older);
    expect(await store.loadAccelerationRun(older), isNotNull);
  });

  test('limit 参数限制返回条数', () async {
    final store = RideStore(useMemory: true);
    for (var i = 0; i < 5; i++) {
      await store.createAccelerationRun(
        _run(startedAt: DateTime(2026, 10, i + 1)),
      );
    }
    final runs = await store.loadAccelerationRuns(limit: 3);
    expect(runs.length, 3);
  });

  test('清空全部成绩会同时删除采样点', () async {
    final store = RideStore(useMemory: true);
    final id = await store.createAccelerationRun(_run());
    await store.insertAccelerationSamples(id, _samples(id));

    await store.deleteAllAccelerationRuns();

    expect(await store.loadAccelerationRuns(), isEmpty);
    expect(await store.loadAccelerationSamples(id), isEmpty);
  });

  test('删除演示数据只影响 isDemo 记录', () async {
    final store = RideStore(useMemory: true);
    final real = await store.createAccelerationRun(_run());
    final demo = await store.createAccelerationRun(
      _run(startedAt: DateTime(2026, 10, 2)).copyWith(isDemo: true),
    );
    await store.insertAccelerationSamples(real, _samples(real));
    await store.insertAccelerationSamples(demo, _samples(demo));

    await store.deleteDemoData();

    final runs = await store.loadAccelerationRuns();
    expect(runs.length, 1);
    expect(runs.first.id, real);
    expect(await store.loadAccelerationSamples(demo), isEmpty);
    expect((await store.loadAccelerationSamples(real)).length, 4);
  });

  test('无效成绩也能保存并保留原因', () async {
    final store = RideStore(useMemory: true);
    final id = await store.createAccelerationRun(
      _run(valid: false, resultMs: 6120),
    );
    final loaded = await store.loadAccelerationRun(id);
    expect(loaded, isNotNull);
    expect(loaded!.valid, isFalse);
    expect(loaded.invalidReason, contains('速度回落'));
  });
}
