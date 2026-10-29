import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../models/ride_sample.dart';
import '../models/ride_session.dart';
import '../utils/geo.dart';
import 'lean_angle_estimator.dart';
import 'location_service.dart';
import 'ride_store.dart';
import 'sensor_service.dart';

enum RecorderState {
  idle,
  preparing,
  calibrating,
  recording,
  paused,
  saving,
  failed,
  finished,
}

class TrackPoint {
  const TrackPoint({
    required this.lat,
    required this.lon,
    required this.leanDeg,
  });

  final double lat;
  final double lon;
  final double leanDeg;
}

class RideRecorder extends ChangeNotifier {
  RideRecorder({
    required this.store,
    required this.locationService,
    required this.sensorService,
    this.calibrationSeconds = 3,
  });

  final RideStore store;
  final LocationService locationService;
  final SensorService sensorService;

  /// 校准时长（秒），可在设置里调整。
  final int calibrationSeconds;

  int get calibrationDurationMs => calibrationSeconds.clamp(2, 5) * 1000;

  final LeanAngleEstimator _estimator = LeanAngleEstimator();
  final List<Vec3> _calibrationAccel = [];
  final List<Vec3> _calibrationGyro = [];
  final List<TrackPoint> _track = [];

  RecorderState state = RecorderState.idle;
  double calibrationProgress = 0;
  String? errorMessage;
  String? calibrationWarning;
  String? permissionMessage;
  String? gpsError;
  LeanCalibration? calibration;
  bool backgroundAllowed = false;

  double _leanDeg = 0;
  double _displaySpeedMps = 0;
  double _maxSpeedMps = 0;
  double _distanceM = 0;
  double _maxLeanLeft = 0;
  double _maxLeanRight = 0;
  double _elevationGain = 0;
  double _movingSeconds = 0;
  double? _gpsAccuracy;
  double? _smoothedAltitude;

  int _sampleCount = 0;
  int? _sessionId;
  int? _finishedSessionId;
  DateTime? _sessionStart;
  Stopwatch? _clock;
  DateTime? _calibrationStarted;
  DateTime? _lastAccelAt;
  DateTime? _lastSampleAt;
  DateTime? _lastTrackAt;
  DateTime? _positionAt;
  DateTime? _lastDistanceAt;
  Vec3? _latestGyro;
  Position? _latestPosition;
  Position? _lastDistancePosition;

  Timer? _calibrationTimer;
  Timer? _uiTimer;
  Timer? _sampleTimer;
  StreamSubscription<Position>? _positionSubscription;
  bool _writingSample = false;
  bool _disposed = false;

  int? get finishedSessionId => _finishedSessionId;
  int? get sessionId => _sessionId;
  int get elapsedSeconds => _clock?.elapsed.inSeconds ?? 0;
  int get sampleCount => _sampleCount;
  double get leanDeg => _leanDeg;
  double get distanceM => _distanceM;
  double get maxLeanLeftDeg => _maxLeanLeft;
  double get maxLeanRightDeg => _maxLeanRight;
  double get elevationGainM => _elevationGain;
  double? get gpsAccuracyM => _gpsAccuracy;
  int get movingSeconds => _movingSeconds.round();
  List<TrackPoint> get track => List.unmodifiable(_track);

  double get speedKmh =>
      gpsFresh ? (_displaySpeedMps * 3.6).clamp(0, 350).toDouble() : 0.0;

  double get avgSpeedKmh => _movingSeconds <= 0
      ? 0.0
      : (_distanceM / _movingSeconds * 3.6).clamp(0, 350).toDouble();

  double get maxSpeedKmh => (_maxSpeedMps * 3.6).clamp(0, 350).toDouble();

  double? get currentLatitude => _latestPosition?.latitude;
  double? get currentLongitude => _latestPosition?.longitude;
  TrackPoint? get lastTrackPoint => _track.isEmpty ? null : _track.last;

  bool get gpsFresh =>
      _positionAt != null &&
      DateTime.now().difference(_positionAt!) < const Duration(seconds: 6);

  bool get sensorFresh =>
      _lastAccelAt != null &&
      DateTime.now().difference(_lastAccelAt!) < const Duration(seconds: 2);

  Future<void> start() async {
    if (state != RecorderState.idle && state != RecorderState.failed) {
      return;
    }
    _resetForNewRide();
    state = RecorderState.preparing;
    _notify();

    try {
      final access = await locationService.ensureAccess();
      if (_disposed || state != RecorderState.preparing) {
        return;
      }
      backgroundAllowed = access.background;
      permissionMessage = access.message;
      if (!access.canRecord) {
        errorMessage = access.message;
        state = RecorderState.failed;
        _notify();
        return;
      }

      sensorService.start(onAccel: _onAccel, onGyro: _onGyro);
      state = RecorderState.calibrating;
      calibrationProgress = 0;
      _calibrationStarted = DateTime.now();
      _notify();

      _calibrationTimer = Timer.periodic(const Duration(milliseconds: 100), (
        timer,
      ) {
        final started = _calibrationStarted;
        if (started == null) {
          timer.cancel();
          return;
        }
        final elapsed = DateTime.now().difference(started).inMilliseconds;
        calibrationProgress = (elapsed / calibrationDurationMs)
            .clamp(0.0, 1.0)
            .toDouble();
        _notify();
        if (elapsed >= calibrationDurationMs) {
          timer.cancel();
          unawaited(_finishCalibration());
        }
      });
    } catch (error) {
      await _fail('启动失败：$error');
    }
  }

  void pause() {
    if (state != RecorderState.recording) {
      return;
    }
    state = RecorderState.paused;
    _clock?.stop();
    _uiTimer?.cancel();
    _sampleTimer?.cancel();
    unawaited(_positionSubscription?.cancel());
    _positionSubscription = null;
    unawaited(sensorService.stop());
    _notify();
  }

  void resume() {
    if (state != RecorderState.paused || calibration == null) {
      return;
    }
    _estimator.reset(calibration!);
    _latestGyro = null;
    _lastAccelAt = null;
    _lastDistancePosition = null;
    _lastDistanceAt = null;
    sensorService.start(onAccel: _onAccel, onGyro: _onGyro);
    _attachLocationStream();
    _clock?.start();
    state = RecorderState.recording;
    _startTimers();
    _notify();
  }

  Future<int?> stop() async {
    if (state != RecorderState.recording && state != RecorderState.paused) {
      return _finishedSessionId;
    }
    state = RecorderState.saving;
    _calibrationTimer?.cancel();
    _uiTimer?.cancel();
    _sampleTimer?.cancel();
    await _positionSubscription?.cancel();
    _positionSubscription = null;
    await sensorService.stop();
    _clock?.stop();

    await _writeSample();

    final id = _sessionId;
    final started = _sessionStart;
    if (id == null || started == null) {
      state = RecorderState.finished;
      _notify();
      return null;
    }

    final session = RideSession(
      id: id,
      startedAt: started,
      endedAt: DateTime.now(),
      distanceM: _distanceM,
      durationS: _clock?.elapsed.inSeconds ?? 0,
      movingS: _movingSeconds.round(),
      maxSpeedMps: _maxSpeedMps,
      avgSpeedMps: _movingSeconds > 0 ? _distanceM / _movingSeconds : 0.0,
      maxLeanLeftDeg: _maxLeanLeft,
      maxLeanRightDeg: _maxLeanRight,
      elevationGainM: _elevationGain,
      sampleCount: _sampleCount,
      isDemo: false,
    );

    try {
      await store.updateSession(session);
    } catch (error) {
      errorMessage = '保存行程失败：$error';
      state = RecorderState.paused;
      _notify();
      return null;
    }

    _finishedSessionId = id;
    state = RecorderState.finished;
    _notify();
    return id;
  }

  /// Cancels preparation/calibration without creating a ride.
  Future<void> cancel() async {
    if (state == RecorderState.recording || state == RecorderState.paused) {
      return;
    }
    _calibrationTimer?.cancel();
    _uiTimer?.cancel();
    _sampleTimer?.cancel();
    await _positionSubscription?.cancel();
    _positionSubscription = null;
    await sensorService.stop();
    _clock?.stop();
    state = RecorderState.idle;
    errorMessage = null;
    _notify();
  }

  Future<void> _finishCalibration() async {
    if (_disposed || state != RecorderState.calibrating) {
      return;
    }
    final result = LeanCalibration.fromSamples(
      accelSamples: List.of(_calibrationAccel),
      gyroSamples: List.of(_calibrationGyro),
    );
    calibration = result;
    calibrationWarning = result.warning;
    if (!result.usable) {
      await _fail(result.warning ?? '校准失败，请扶正车身重试');
      return;
    }

    _estimator.reset(result);
    _latestGyro = null;
    _lastAccelAt = null;
    _clock = Stopwatch()..start();
    _sessionStart = DateTime.now();

    try {
      _sessionId = await store.createSession(
        RideSession(startedAt: _sessionStart!, isDemo: false),
      );
    } catch (error) {
      await _fail('创建行程失败：$error');
      return;
    }

    state = RecorderState.recording;
    _attachLocationStream();
    _startTimers();
    _notify();
  }

  void _attachLocationStream() {
    _positionSubscription?.cancel();
    _positionSubscription = locationService.positionStream().listen(
      _onPosition,
      onError: (Object error) {
        gpsError = '定位数据中断，正在等待信号';
        _notify();
      },
    );
  }

  void _startTimers() {
    _uiTimer?.cancel();
    _sampleTimer?.cancel();
    _uiTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (state == RecorderState.recording) {
        _notify();
      }
    });
    _sampleTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (state == RecorderState.recording) {
        unawaited(_writeSample());
      }
    });
  }

  void _onAccel(AccelerometerEvent event) {
    final accel = Vec3(event.x, event.y, event.z);
    if (state == RecorderState.calibrating) {
      _calibrationAccel.add(accel);
      if (_calibrationAccel.length > 500) {
        _calibrationAccel.removeAt(0);
      }
      // 校准期间用原始重力倾角驱动 UI 水平泡，帮用户扶正车身；
      // 此时零位未确定，原始值正好反映车身的物理倾斜。
      _leanDeg =
          math.atan2(
            -accel.x,
            math.sqrt(accel.y * accel.y + accel.z * accel.z),
          ) *
          180 /
          math.pi;
      return;
    }
    if (state != RecorderState.recording) {
      return;
    }
    final now = DateTime.now();
    final dt = _lastAccelAt == null
        ? 0.02
        : now.difference(_lastAccelAt!).inMilliseconds / 1000.0;
    _lastAccelAt = now;

    final lean = _estimator.update(
      accel: accel,
      gyro: _latestGyro,
      dtSeconds: dt,
    );
    _leanDeg = lean;
    if (lean < -5) {
      _maxLeanLeft = math.max(_maxLeanLeft, -lean);
    }
    if (lean > 5) {
      _maxLeanRight = math.max(_maxLeanRight, lean);
    }
  }

  void _onGyro(GyroscopeEvent event) {
    final gyro = Vec3(event.x, event.y, event.z);
    if (state == RecorderState.calibrating) {
      _calibrationGyro.add(gyro);
      if (_calibrationGyro.length > 500) {
        _calibrationGyro.removeAt(0);
      }
    }
    _latestGyro = gyro;
  }

  void _onPosition(Position position) {
    if (state != RecorderState.recording) {
      return;
    }
    final now = DateTime.now();
    _latestPosition = position;
    _positionAt = now;
    _gpsAccuracy = position.accuracy;
    gpsError = null;

    if (position.accuracy <= 35) {
      final speed = position.speed.isFinite
          ? position.speed.clamp(0.0, 90.0).toDouble()
          : 0.0;
      _displaySpeedMps += (speed - _displaySpeedMps) * 0.4;
      if (speed > _maxSpeedMps && speed < 90) {
        _maxSpeedMps = speed;
      }

      final last = _lastDistancePosition;
      final lastAt = _lastDistanceAt;
      if (last != null && lastAt != null) {
        final elapsed = now.difference(lastAt).inMilliseconds / 1000.0;
        final moved = distanceMeters(
          last.latitude,
          last.longitude,
          position.latitude,
          position.longitude,
        );
        if (elapsed > 0.1 &&
            isPlausibleJump(distanceM: moved, elapsedSeconds: elapsed) &&
            moved < 500) {
          _distanceM += moved;
          if (speed > 1.5) {
            _movingSeconds += elapsed.clamp(0.0, 4.0);
          }
          _addTrackPoint(position, moved);
        }
      } else {
        _addTrackPoint(position, 0);
      }
      _lastDistancePosition = position;
      _lastDistanceAt = now;
      _updateElevation(position);
    }

    if (_lastSampleAt == null ||
        now.difference(_lastSampleAt!) >= const Duration(milliseconds: 900)) {
      unawaited(_writeSample());
    }
    _notify();
  }

  void _addTrackPoint(Position position, double moved) {
    final now = DateTime.now();
    final lastAt = _lastTrackAt;
    if (moved < 2.5 &&
        lastAt != null &&
        now.difference(lastAt) < const Duration(seconds: 3)) {
      return;
    }
    _track.add(
      TrackPoint(
        lat: position.latitude,
        lon: position.longitude,
        leanDeg: _leanDeg,
      ),
    );
    if (_track.length > 20000) {
      _track.removeRange(0, 1000);
    }
    _lastTrackAt = now;
  }

  void _updateElevation(Position position) {
    if (position.accuracy > 30 || !position.altitude.isFinite) {
      return;
    }
    final smoothed = _smoothedAltitude;
    if (smoothed == null) {
      _smoothedAltitude = position.altitude;
      return;
    }
    final next = smoothed + (position.altitude - smoothed) * 0.25;
    final delta = next - smoothed;
    if (delta > 1.2) {
      _elevationGain += delta;
    }
    _smoothedAltitude = next;
  }

  Future<void> _writeSample() async {
    final id = _sessionId;
    final started = _sessionStart;
    if (_writingSample ||
        id == null ||
        started == null ||
        (state != RecorderState.recording && state != RecorderState.saving)) {
      return;
    }
    _writingSample = true;
    try {
      final now = DateTime.now();
      final fresh =
          _positionAt != null &&
          now.difference(_positionAt!) < const Duration(seconds: 6);
      final position = fresh ? _latestPosition : null;
      final sample = RideSample(
        sessionId: id,
        tMs: now.difference(started).inMilliseconds,
        leanDeg: double.parse(_leanDeg.toStringAsFixed(2)),
        lat: position?.latitude,
        lon: position?.longitude,
        altitudeM: position?.altitude,
        speedMps: position == null ? null : _displaySpeedMps,
        accuracyM: position?.accuracy,
      );
      await store.insertSample(sample);
      _sampleCount++;
      _lastSampleAt = now;
    } catch (_) {
      // Losing one sample is not fatal; the next timer tick retries.
    } finally {
      _writingSample = false;
    }
  }

  Future<void> _fail(String message) async {
    _calibrationTimer?.cancel();
    _uiTimer?.cancel();
    _sampleTimer?.cancel();
    await _positionSubscription?.cancel();
    _positionSubscription = null;
    await sensorService.stop();
    _clock?.stop();
    errorMessage = message;
    state = RecorderState.failed;
    _notify();
  }

  void _resetForNewRide() {
    _calibrationTimer?.cancel();
    _uiTimer?.cancel();
    _sampleTimer?.cancel();
    unawaited(_positionSubscription?.cancel());
    _positionSubscription = null;
    unawaited(sensorService.stop());

    _calibrationAccel.clear();
    _calibrationGyro.clear();
    _track.clear();
    _estimator.reset(
      const LeanCalibration(
        accelSampleCount: 0,
        gravityMagnitude: 0.0,
        zeroRollDeg: 0.0,
        mount: LeanMount.verticalScreenFacingRider,
        gyroAxisIndex: 2,
        gyroAxisSign: -1,
        gyroBiasRaw: 0.0,
        usable: false,
      ),
    );
    calibration = null;
    calibrationWarning = null;
    permissionMessage = null;
    gpsError = null;
    errorMessage = null;
    backgroundAllowed = false;
    calibrationProgress = 0;
    _leanDeg = 0;
    _displaySpeedMps = 0;
    _maxSpeedMps = 0;
    _distanceM = 0;
    _maxLeanLeft = 0;
    _maxLeanRight = 0;
    _elevationGain = 0;
    _movingSeconds = 0;
    _gpsAccuracy = null;
    _smoothedAltitude = null;
    _sampleCount = 0;
    _sessionId = null;
    _finishedSessionId = null;
    _sessionStart = null;
    _clock = null;
    _calibrationStarted = null;
    _lastAccelAt = null;
    _lastSampleAt = null;
    _lastTrackAt = null;
    _positionAt = null;
    _lastDistanceAt = null;
    _latestGyro = null;
    _latestPosition = null;
    _lastDistancePosition = null;
    _writingSample = false;
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _calibrationTimer?.cancel();
    _uiTimer?.cancel();
    _sampleTimer?.cancel();
    unawaited(_positionSubscription?.cancel());
    unawaited(sensorService.stop());
    super.dispose();
  }
}
