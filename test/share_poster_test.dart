import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motolean/models/acceleration_run.dart';
import 'package:motolean/models/ride_sample.dart';
import 'package:motolean/models/ride_session.dart';
import 'package:motolean/services/settings_service.dart';
import 'package:motolean/services/share_image.dart';
import 'package:motolean/theme.dart';
import 'package:motolean/utils/ride_analytics.dart';
import 'package:motolean/widgets/share_poster.dart';

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

AccelerationRun _run() => AccelerationRun(
  id: 1,
  startedAt: DateTime(2026, 10, 1, 10, 12),
  targetSpeedKmh: 100,
  resultMs: 4870,
  result60Ms: 2310,
  result130Ms: 6120,
  distanceM: 268,
  maxSpeedKmh: 118,
  gradePercent: 1.4,
  gpsAccuracyM: 6,
);

void main() {
  Future<GlobalKey> pumpPoster(
    WidgetTester tester,
    Widget poster, {
    Size size = const Size(800, 1600),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Center(child: RepaintBoundary(key: key, child: poster)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return key;
  }

  testWidgets('行程总结长图包含关键数据', (tester) async {
    await pumpPoster(
      tester,
      RideSharePoster(
        session: _session(),
        bands: RideAnalytics.leanBands(_samples()),
        corners: RideAnalytics.cornerCount(_samples()),
        settings: SettingsService(),
      ),
    );

    expect(find.text('21.8'), findsOneWidget);
    expect(find.text('本次骑行 · 里程'), findsOneWidget);
    expect(find.text('最大左倾'), findsOneWidget);
    expect(find.text('最大右倾'), findsOneWidget);
    expect(find.text('过弯次数'), findsOneWidget);
    expect(find.text('倾角分布'), findsOneWidget);
  });

  testWidgets('零百成绩长图包含关键数据', (tester) async {
    await pumpPoster(
      tester,
      AccelerationSharePoster(run: _run(), settings: SettingsService()),
      size: const Size(800, 1200),
    );

    expect(find.text('4.87'), findsOneWidget);
    expect(find.text('0–100 km/h'), findsOneWidget);
    expect(find.text('2.31 s'), findsOneWidget);
    expect(find.text('6.12 s'), findsOneWidget);
    expect(find.text('268 m'), findsOneWidget);
  });

  testWidgets('保存弹窗三个操作齐全且不溢出', (tester) async {
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showSharePosterDialog(
                  context,
                  poster: AccelerationSharePoster(
                    run: _run(),
                    settings: SettingsService(),
                  ),
                  fileName: 'motolean_accel.png',
                  subject: '摩倾零百成绩',
                  text: '摩倾 · 零百 4.87 秒',
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('保存长图'), findsOneWidget);
    expect(find.text('保存到相册'), findsOneWidget);
    expect(find.text('更多分享方式'), findsOneWidget);
    expect(find.text('复制文案'), findsOneWidget);
  });

  testWidgets('海报可以按 3 倍密度导出 PNG', (tester) async {
    final key = await pumpPoster(
      tester,
      RideSharePoster(
        session: _session(),
        bands: RideAnalytics.leanBands(_samples()),
        corners: RideAnalytics.cornerCount(_samples()),
        settings: SettingsService(),
      ),
    );

    await tester.runAsync(() async {
      final png = await ShareImage.capture(key);
      expect(png.length, greaterThan(1000));

      final codec = await ui.instantiateImageCodec(png);
      final frame = await codec.getNextFrame();
      // 海报逻辑宽度 360，3 倍导出约 1080px
      expect(frame.image.width, 1080);
      expect(frame.image.height, greaterThan(1200));
    });
  });
}
