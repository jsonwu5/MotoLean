import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motolean/app.dart';
import 'package:motolean/screens/record_screen.dart';
import 'package:motolean/services/ride_store.dart';
import 'package:motolean/services/settings_service.dart';
import 'package:motolean/theme.dart';
import 'package:motolean/widgets/lean_gauge.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  testWidgets('home screen builds without a database', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MotoLeanApp(store: RideStore(), settings: SettingsService()),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('摩倾'), findsOneWidget);
    expect(find.text('开始记录'), findsWidgets);
    expect(find.text('骑行记录'), findsOneWidget);
  });

  testWidgets('record intro builds on a phone-sized screen', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: RecordScreen(store: RideStore(), settings: SettingsService()),
      ),
    );
    await tester.pump();

    expect(find.text('准备记录'), findsOneWidget);
    expect(find.textContaining('先固定好手机'), findsOneWidget);
    expect(find.text('开始校准并记录'), findsOneWidget);
  });

  testWidgets('lean gauge shows signed lean and limits', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const Scaffold(
          body: LeanGauge(
            leanDeg: 32,
            maxLeftDeg: 41,
            maxRightDeg: 44,
          ),
        ),
      ),
    );
    expect(find.text('+32°'), findsOneWidget);
    expect(find.text('右倾'), findsOneWidget);
    expect(find.text('41°'), findsOneWidget);
    expect(find.text('44°'), findsOneWidget);
  });
}
