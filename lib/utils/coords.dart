import 'dart:math' as math;

/// 国内地图（腾讯 / 高德）使用 GCJ-02「火星坐标」，
/// 而手机 GPS 与 GPX 导出使用 WGS-84。
///
/// 两者在国内相差约 300–700 米，展示前必须转换，否则轨迹会整体偏移。
class GeoCoords {
  const GeoCoords._();

  static const double _a = 6378245.0;
  static const double _ee = 0.00669342162296594323;

  /// 境外坐标不做偏移。
  static bool _outOfChina(double lat, double lon) =>
      lon < 72.004 || lon > 137.8347 || lat < 0.8293 || lat > 55.8271;

  static double _transformLat(double x, double y) {
    var ret =
        -100.0 +
        2.0 * x +
        3.0 * y +
        0.2 * y * y +
        0.1 * x * y +
        0.2 * math.sqrt(x.abs());
    ret +=
        (20.0 * math.sin(6.0 * x * math.pi) +
            20.0 * math.sin(2.0 * x * math.pi)) *
        2.0 /
        3.0;
    ret +=
        (20.0 * math.sin(y * math.pi) +
            40.0 * math.sin(y / 3.0 * math.pi)) *
        2.0 /
        3.0;
    ret +=
        (160.0 * math.sin(y / 12.0 * math.pi) +
            320 * math.sin(y * math.pi / 30.0)) *
        2.0 /
        3.0;
    return ret;
  }

  static double _transformLon(double x, double y) {
    var ret =
        300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * math.sqrt(x.abs());
    ret +=
        (20.0 * math.sin(6.0 * x * math.pi) +
            20.0 * math.sin(2.0 * x * math.pi)) *
        2.0 /
        3.0;
    ret +=
        (20.0 * math.sin(x * math.pi) +
            40.0 * math.sin(x / 3.0 * math.pi)) *
        2.0 /
        3.0;
    ret +=
        (150.0 * math.sin(x / 12.0 * math.pi) +
            300.0 * math.sin(x / 30.0 * math.pi)) *
        2.0 /
        3.0;
    return ret;
  }

  /// WGS-84 → GCJ-02（用于把 GPS 轨迹画到腾讯地图上）。
  static (double lat, double lon) toGcj({
    required double lat,
    required double lon,
  }) {
    if (_outOfChina(lat, lon)) {
      return (lat, lon);
    }
    var dLat = _transformLat(lon - 105.0, lat - 35.0);
    var dLon = _transformLon(lon - 105.0, lat - 35.0);
    final radLat = lat / 180.0 * math.pi;
    var magic = math.sin(radLat);
    magic = 1 - _ee * magic * magic;
    final sqrtMagic = math.sqrt(magic);
    dLat = (dLat * 180.0) / ((_a * (1 - _ee)) / (magic * sqrtMagic) * math.pi);
    dLon = (dLon * 180.0) / (_a / sqrtMagic * math.cos(radLat) * math.pi);
    return (lat + dLat, lon + dLon);
  }

  /// GCJ-02 → WGS-84（用于把地图上取到的点转回真实坐标）。
  /// 迭代逼近，误差在 1 米以内。
  static (double lat, double lon) toWgs({
    required double lat,
    required double lon,
  }) {
    if (_outOfChina(lat, lon)) {
      return (lat, lon);
    }
    var wLat = lat;
    var wLon = lon;
    for (var i = 0; i < 3; i++) {
      final (gLat, gLon) = toGcj(lat: wLat, lon: wLon);
      wLat += lat - gLat;
      wLon += lon - gLon;
    }
    return (wLat, wLon);
  }
}
