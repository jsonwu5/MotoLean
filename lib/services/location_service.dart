import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

enum LocationReadiness { ready, serviceDisabled, denied, deniedForever }

class LocationAccessResult {
  const LocationAccessResult({
    required this.readiness,
    required this.background,
    required this.message,
  });

  final LocationReadiness readiness;
  final bool background;
  final String message;

  bool get canRecord => readiness == LocationReadiness.ready;
}

class LocationService {
  Future<LocationAccessResult> ensureAccess() async {
    if (kIsWeb) {
      return _ensureWebAccess();
    }

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return const LocationAccessResult(
        readiness: LocationReadiness.serviceDisabled,
        background: false,
        message: '系统定位服务未开启，请先打开定位。',
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      return const LocationAccessResult(
        readiness: LocationReadiness.denied,
        background: false,
        message: '需要定位权限才能记录速度与轨迹。',
      );
    }
    if (permission == LocationPermission.deniedForever) {
      return const LocationAccessResult(
        readiness: LocationReadiness.deniedForever,
        background: false,
        message: '定位权限已被永久拒绝，请到系统设置中开启。',
      );
    }

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      await Permission.notification.request();
    }

    var background = permission == LocationPermission.always;
    if (!kIsWeb && !background) {
      final always = await Permission.locationAlways.request();
      background = always.isGranted;
    }

    return LocationAccessResult(
      readiness: LocationReadiness.ready,
      background: background,
      message: background
          ? '已获得前台与后台定位权限。'
          : '已获得前台定位权限；选择“始终允许”才能在熄屏后持续记录。',
    );
  }

  Future<LocationAccessResult> _ensureWebAccess() async {
    try {
      final permission = await Geolocator.requestPermission().timeout(
        const Duration(seconds: 15),
      );
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return const LocationAccessResult(
          readiness: LocationReadiness.denied,
          background: false,
          message: '浏览器需要定位权限才能记录。',
        );
      }
      return const LocationAccessResult(
        readiness: LocationReadiness.ready,
        background: false,
        message: '浏览器预览仅支持前台记录；后台持续记录请在手机 App 中使用。',
      );
    } catch (_) {
      return const LocationAccessResult(
        readiness: LocationReadiness.denied,
        background: false,
        message: '浏览器定位权限请求超时或被拒绝。',
      );
    }
  }

  Stream<Position> positionStream() {
    if (kIsWeb) {
      return Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 1,
        ),
      );
    }
    final settings = defaultTargetPlatform == TargetPlatform.android
        ? AndroidSettings(
            accuracy: LocationAccuracy.bestForNavigation,
            distanceFilter: 1,
            intervalDuration: const Duration(seconds: 1),
            foregroundNotificationConfig: const ForegroundNotificationConfig(
              notificationTitle: '摩倾正在记录',
              notificationText: '速度、倾角与轨迹持续记录中',
              enableWakeLock: true,
              notificationIcon: AndroidResource(
                name: 'ic_stat_lean',
                defType: 'drawable',
              ),
            ),
          )
        : AppleSettings(
            accuracy: LocationAccuracy.bestForNavigation,
            distanceFilter: 1,
            activityType: ActivityType.automotiveNavigation,
            pauseLocationUpdatesAutomatically: false,
            showBackgroundLocationIndicator: true,
            allowBackgroundLocationUpdates: true,
          );
    return Geolocator.getPositionStream(locationSettings: settings);
  }

  Future<void> openSettings() async {
    await openAppSettings();
  }

  Future<void> openLocationSettings() async {
    await Geolocator.openLocationSettings();
  }
}
