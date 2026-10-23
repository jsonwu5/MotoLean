import 'dart:async';

import 'package:sensors_plus/sensors_plus.dart';

typedef AccelCallback = void Function(AccelerometerEvent event);
typedef GyroCallback = void Function(GyroscopeEvent event);

class SensorService {
  StreamSubscription<AccelerometerEvent>? _accelSubscription;
  StreamSubscription<GyroscopeEvent>? _gyroSubscription;

  bool get isRunning => _accelSubscription != null;

  void start({
    required AccelCallback onAccel,
    required GyroCallback onGyro,
  }) {
    _accelSubscription?.cancel();
    _gyroSubscription?.cancel();
    const period = Duration(milliseconds: 20); // ~50 Hz
    _accelSubscription = accelerometerEventStream(samplingPeriod: period)
        .listen(onAccel, onError: (Object _) {});
    _gyroSubscription = gyroscopeEventStream(samplingPeriod: period)
        .listen(onGyro, onError: (Object _) {});
  }

  Future<void> stop() async {
    final accel = _accelSubscription;
    final gyro = _gyroSubscription;
    _accelSubscription = null;
    _gyroSubscription = null;
    await accel?.cancel();
    await gyro?.cancel();
  }
}
