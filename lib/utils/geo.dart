import 'dart:math' as math;

const double earthRadiusMeters = 6371000.0;

/// Great-circle distance between two WGS84 points, in meters.
double distanceMeters(
  double lat1,
  double lon1,
  double lat2,
  double lon2,
) {
  final dLat = _radians(lat2 - lat1);
  final dLon = _radians(lon2 - lon1);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_radians(lat1)) *
          math.cos(_radians(lat2)) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  return 2 * earthRadiusMeters * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

/// Reject impossible jumps caused by GPS glitches.
bool isPlausibleJump({
  required double distanceM,
  required double elapsedSeconds,
}) {
  if (elapsedSeconds <= 0) {
    return false;
  }
  final speed = distanceM / elapsedSeconds;
  return speed < 70; // 252 km/h, well above any mountain-road speed
}

double _radians(double degrees) => degrees * math.pi / 180.0;
