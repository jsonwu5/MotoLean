import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motolean/models/ride_sample.dart';
import 'package:motolean/screens/track_playback_screen.dart';
import 'package:motolean/services/settings_service.dart';
import 'package:motolean/theme.dart';
import 'package:motolean/utils/coords.dart';
import 'package:motolean/widgets/ride_playback_map.dart';

RideSample _sample(int i, {double? lat, double? lon, double lean = 20}) =>
    RideSample(
      sessionId: 1,
      tMs: i * 1000,
      leanDeg: lean,
      lat: lat,
      lon: lon,
      speedMps: 12 + i.toDouble(),
      altitudeM: 300 + i.toDouble(),
    );

void main() {
  group('坐标转换', () {
    test('国内坐标会偏移，境外坐标保持不变', () {
      // 长沙附近
      final (gLat, gLon) = GeoCoords.toGcj(lat: 28.19, lon: 112.98);
      expect(gLat, isNot(closeTo(28.19, 1e-6)));
      expect(gLon, isNot(closeTo(112.98, 1e-6)));

      // 往返误差应在 1 米量级
      final (wLat, wLon) = GeoCoords.toWgs(lat: gLat, lon: gLon);
      expect(wLat, closeTo(28.19, 1e-5));
      expect(wLon, closeTo(112.98, 1e-5));

      // 境外不偏移
      final (nLat, nLon) = GeoCoords.toGcj(lat: 48.85, lon: 2.35);
      expect(nLat, 48.85);
      expect(nLon, 2.35);
    });
  });

  group('回放轨迹点', () {
    test('过滤没有定位的采样并按时间排序', () {
      final points = buildPlaybackPoints([
        _sample(2, lat: 28.20, lon: 112.99),
        _sample(0, lat: 28.18, lon: 112.97),
        _sample(1), // 无定位，应被丢弃
      ]);
      expect(points, hasLength(2));
      expect(points.first.tMs, 0);
      expect(points.last.tMs, 2000);
    });

    test('全部没有定位时返回空列表', () {
      expect(buildPlaybackPoints([_sample(0), _sample(1)]), isEmpty);
    });
  });

  testWidgets('回放页在未配置 Key 时给出提示', (tester) async {
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: TrackPlaybackScreen(
          samples: [
            _sample(0, lat: 28.18, lon: 112.97),
            _sample(1, lat: 28.19, lon: 112.98),
            _sample(2, lat: 28.20, lon: 112.99),
          ],
          settings: SettingsService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('轨迹回放'), findsOneWidget);
    expect(find.text('需要腾讯地图 Key 才能回放轨迹'), findsOneWidget);
  });
}
