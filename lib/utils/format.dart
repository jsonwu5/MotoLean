String formatDuration(int totalSeconds) {
  final seconds = totalSeconds.clamp(0, 359999);
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  if (h > 0) {
    return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
  return '$m:${s.toString().padLeft(2, '0')}';
}

String formatDistance(double meters) {
  if (meters >= 1000) {
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }
  return '${meters.round()} m';
}

String formatSpeed(double metersPerSecond) {
  return (metersPerSecond * 3.6).clamp(0, 400).toStringAsFixed(0);
}

String formatLean(double degrees) {
  final rounded = degrees.round();
  if (rounded > 0) {
    return '+$rounded°';
  }
  return '$rounded°';
}

const _weekdays = ['一', '二', '三', '四', '五', '六', '日'];

String formatDateWithWeekday(DateTime time) =>
    '${time.month}月${time.day}日 · 周${_weekdays[time.weekday - 1]}';

String formatClock(DateTime time) {
  final hour = time.hour.toString().padLeft(2, '0');
  final minute = time.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

String formatFileStamp(DateTime time) {
  final month = time.month.toString().padLeft(2, '0');
  final day = time.day.toString().padLeft(2, '0');
  final hour = time.hour.toString().padLeft(2, '0');
  final minute = time.minute.toString().padLeft(2, '0');
  return '${time.year}$month${day}_$hour$minute';
}
