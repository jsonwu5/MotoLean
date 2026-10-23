import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motolean/app.dart';
import 'package:motolean/models/ride_sample.dart';
import 'package:motolean/models/ride_session.dart';
import 'package:motolean/screens/summary_screen.dart';
import 'package:motolean/services/ride_store.dart';
import 'package:motolean/theme.dart';

class _FakeStore extends RideStore {
  _FakeStore({required this.session, required this.samples});

  final RideSession session;
  final List<RideSample> samples;

  @override
  Future<List<RideSession>> loadSessions() async => [session];

  @override
  Future<RideSession?> loadSession(int id) async => session;

  @override
  Future<List<RideSample>> loadSamples(int sessionId) async => samples;
}

RideSession _session() => RideSession(
      id: 1,
      startedAt: DateTime(2026, 10, 1, 9, 30),
      endedAt: DateTime(2026, 10, 1, 9, 57),
      distanceM: 21800,
      durationS: 1620,
      movingS: 1500,
      maxSpeedMps: 24.5,
      avgSpeedMps: 14.5,
      maxLeanLeftDeg: 41,
      maxLeanRightDeg: 44,
      elevationGainM: 380,
      sampleCount: 120,
      isDemo: false,
    );

List<RideSample> _samples() => [
      for (var i = 0; i < 120; i++)
        RideSample(
          sessionId: 1,
          tMs: i * 1000,
          leanDeg: 40 * (i % 30 < 15 ? 1 : -1) * (i % 15 / 15),
          speedMps: 12 + (i % 20) * 0.4,
        ),
    ];

void main() {
  void usePhoneSize(WidgetTester tester) {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  testWidgets('home renders a saved session card', (tester) async {
    usePhoneSize(tester);
    final store = _FakeStore(session: _session(), samples: _samples());

    await tester.pumpWidget(MotoLeanApp(store: store));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('10月1日'), findsOneWidget);
    expect(find.text('44°'), findsOneWidget);
    expect(find.text('21.8 km'), findsOneWidget);
    expect(find.text('1'), findsOneWidget); // session count badge
  });

  testWidgets('summary renders stats, lean bands and speed chart',
      (tester) async {
    usePhoneSize(tester);
    final store = _FakeStore(session: _session(), samples: _samples());

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: SummaryScreen(store: store, sessionId: 1),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('行程总结'), findsOneWidget);
    expect(find.text('本次骑行'), findsOneWidget);
    expect(find.text('最大右倾'), findsOneWidget);
    expect(find.text('最大左倾'), findsOneWidget);
    expect(find.text('本次行程没有可用的 GPS 轨迹'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('倾角分布'),
      260,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('倾角分布'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('速度曲线'),
      260,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('速度曲线'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('导出 GPX'),
      260,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('导出 GPX'), findsOneWidget);
  });
}
