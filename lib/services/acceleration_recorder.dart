import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../models/acceleration_run.dart';
import '../models/acceleration_sample.dart';
import 'acceleration_timer.dart';
import 'location_service.dart';
import 'ride_store.dart';
import 'settings_service.dart';

enum AccelerationState {
  idle,
  waitingGps,
  ready,
  countdown,
  running,
  saving,
  finished,
  failed,
}

/// 零百测试的采集与状态机。
///
/// 与 [RideRecorder] 平行但独立：零百只关心速度，不需要 IMU 校准与倾角，
/// 也不需要前台服务（测试通常 10 秒内完成，人就在车上看屏幕）。
class AccelerationRecorder extends ChangeNotifier {
  AccelerationRecorder({
    required this.store,
    required this.settings,
    required this.locationService,
  });

  final RideStore store;
  final SettingsService settings;
  final LocationService locationService;

  /// GPS 精度达到该值才允许开始。
  static const double readyAccuracyM = 15;

  /// 判定「已就绪」的速度上限：必须在静止状态。
  static const double stationarySpeedMps = 0.6;

  AccelerationState state = AccelerationState.idle;
  String? errorMessage;

  double? gpsAccuracyM;
  bool gpsOk = false;
  double speedMps = 0;
  bool started = false;
  int elapsedMs = 0;
  int countdownRemaining = 0;
  double targetSpeedKmh = 100;
  bool rollout = false;
  AccelerationResult? result;
  int? savedRunId;

  final List<AccelerationPoint> _samples = [];
  Stopwatch? _stopwatch;
  int? _startMs;
  DateTime? _wallStart;
  Timer? _countdownTimer;
  Timer? _uiTimer;
  StreamSubscription<Position>? _positionSubscription;
  bool _disposed = false;
  bool _finishing = false;

  double get targetMps => targetSpeedKmh / 3.6;

  double get progress =>
      targetMps <= 0 ? 0 : (speedMps / targetMps).clamp(0.0, 1.0).toDouble();

  double get elapsedSeconds => elapsedMs / 1000;

  List<AccelerationPoint> get samples => List.unmodifiable(_samples);

  /// 进入等待 GPS 状态。
  Future<void> prepare() async {
    if (state == AccelerationState.waitingGps ||
        state == AccelerationState.running) {
      return;
    }
    _resetRun();
    targetSpeedKmh = settings.accelTargetSpeedKmh;
    rollout = settings.accelRollout;
    state = AccelerationState.waitingGps;
    errorMessage = null;
    _notify();

    try {
      final access = await locationService.ensureAccess();
      if (_disposed || state != AccelerationState.waitingGps) {
        return;
      }
      if (!access.canRecord) {
        _fail(access.message);
        return;
      }
      _attachStream();
    } catch (error) {
      _fail('定位启动失败：$error');
    }
  }

  /// 关闭倒计时直接开始（供「立即开始」使用）。
  void beginImmediately() {
    if (state != AccelerationState.ready && state != AccelerationState.countdown) {
      return;
    }
    _countdownTimer?.cancel();
    _countdownTimer = null;
    countdownRemaining = 0;
    _beginRun();
  }

  /// 开始倒计时（倒计时秒数为 0 时直接开始）。
  void startCountdown() {
    if (state != AccelerationState.ready) {
      return;
    }
    final seconds = settings.accelCountdownSeconds;
    if (seconds <= 0) {
      _beginRun();
      return;
    }
    state = AccelerationState.countdown;
    countdownRemaining = seconds;
    _notify();
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_disposed) {
        timer.cancel();
        return;
      }
      countdownRemaining--;
      if (countdownRemaining <= 0) {
        timer.cancel();
        _countdownTimer = null;
        _beginRun();
        return;
      }
      _notify();
    });
  }

  /// 手动结束（未达目标也可以结束，结果会标记无效）。
  Future<void> finish() async {
    if (state != AccelerationState.running || _finishing) {
      return;
    }
    _finishing = true;
    state = AccelerationState.saving;
    _uiTimer?.cancel();
    _uiTimer = null;
    _stopwatch?.stop();
    _notify();

    final computed = AccelerationTimer.compute(
      samples: _samples,
      targetSpeedKmh: targetSpeedKmh,
      rollout: rollout,
      accuracyLimitM: settings.gpsAccuracyLimit,
    );
    result = computed;

    if (computed.resultMs == null) {
      // 没有有效成绩就不入库，避免产生无意义的历史记录。
      state = AccelerationState.finished;
      _finishing = false;
      _notify();
      return;
    }

    try {
      final run = AccelerationRun(
        startedAt: _wallStart ?? DateTime.now(),
        targetSpeedKmh: targetSpeedKmh,
        resultMs: computed.resultMs!,
        rollout: rollout,
        result60Ms: computed.result60Ms,
        result130Ms: computed.result130Ms,
        result200Ms: computed.result200Ms,
        distanceM: computed.distanceM,
        maxSpeedKmh:
            computed.maxSpeedMps == null ? null : computed.maxSpeedMps! * 3.6,
        gradePercent: computed.gradePercent,
        gpsAccuracyM: computed.medianAccuracyM,
        startLat: computed.startLat,
        startLon: computed.startLon,
        valid: computed.valid,
        invalidReason: computed.invalidReason,
      );
      final id = await store.createAccelerationRun(run);
      await store.insertAccelerationSamples(
        id,
        [
          for (final point in _samples)
            AccelerationSample(
              runId: id,
              tMs: point.tMs,
              speedKmh: point.speedMps * 3.6,
              accuracyM: point.accuracyM,
              lat: point.lat,
              lon: point.lon,
            ),
        ],
      );
      savedRunId = id;
      state = AccelerationState.finished;
    } catch (error) {
      errorMessage = '保存成绩失败：$error';
      state = AccelerationState.finished;
    } finally {
      _finishing = false;
      _notify();
    }
  }

  /// 取消并回到初始状态（不保存任何数据）。
  Future<void> cancel() async {
    if (state == AccelerationState.running ||
        state == AccelerationState.saving) {
      return;
    }
    await _detachStream();
    _countdownTimer?.cancel();
    _uiTimer?.cancel();
    _stopwatch?.stop();
    _resetRun();
    state = AccelerationState.idle;
    errorMessage = null;
    _notify();
  }

  void _attachStream() {
    _positionSubscription?.cancel();
    _positionSubscription = locationService.positionStream().listen(
      _onPosition,
      onError: (Object error) {
        errorMessage = '定位数据中断，请稍后重试';
        _notify();
      },
    );
  }

  Future<void> _detachStream() async {
    await _positionSubscription?.cancel();
    _positionSubscription = null;
  }

  void _onPosition(Position position) {
    if (_disposed) {
      return;
    }
    final accuracy = position.accuracy;
    gpsAccuracyM = accuracy;
    gpsOk = accuracy <= readyAccuracyM;
    final speed = position.speed.isFinite
        ? position.speed.clamp(0.0, 120.0).toDouble()
        : 0.0;

    if (state == AccelerationState.waitingGps) {
      if (gpsOk && speed < stationarySpeedMps) {
        state = AccelerationState.ready;
      }
      _notify();
      return;
    }

    if (state != AccelerationState.running) {
      _notify();
      return;
    }

    speedMps = speed;
    final tMs = _stopwatch?.elapsedMilliseconds ?? 0;
    _samples.add(
      AccelerationPoint(
        tMs: tMs,
        speedMps: speed,
        accuracyM: accuracy,
        lat: settings.accelRecordTrack ? position.latitude : null,
        lon: settings.accelRecordTrack ? position.longitude : null,
        altitudeM: settings.accelRecordTrack ? position.altitude : null,
      ),
    );

    if (!started && speed >= AccelerationTimer.startSpeedMps) {
      started = true;
      _startMs = tMs;
    }
    if (started) {
      elapsedMs = tMs - (_startMs ?? tMs);
    }

    if (speed >= targetMps) {
      unawaited(finish());
      return;
    }
    _notify();
  }

  void _beginRun() {
    _samples.clear();
    speedMps = 0;
    started = false;
    elapsedMs = 0;
    _startMs = null;
    result = null;
    savedRunId = null;
    _wallStart = DateTime.now();
    _stopwatch = Stopwatch()..start();
    state = AccelerationState.running;
    _uiTimer?.cancel();
    _uiTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (state == AccelerationState.running) {
        _notify();
      }
    });
    _notify();
  }

  void _resetRun() {
    _samples.clear();
    speedMps = 0;
    started = false;
    elapsedMs = 0;
    _startMs = null;
    result = null;
    savedRunId = null;
    _wallStart = null;
    _stopwatch = null;
    _uiTimer?.cancel();
    _uiTimer = null;
    _countdownTimer?.cancel();
    _countdownTimer = null;
    countdownRemaining = 0;
    gpsAccuracyM = null;
    gpsOk = false;
  }

  void _fail(String message) {
    errorMessage = message;
    state = AccelerationState.failed;
    _notify();
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _countdownTimer?.cancel();
    _uiTimer?.cancel();
    unawaited(_detachStream());
    super.dispose();
  }
}
