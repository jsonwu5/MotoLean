import 'package:flutter/material.dart';
import 'package:flutter_tencent_map/flutter_tencent_map.dart';

import '../config/map_config.dart';
import '../services/settings_service.dart';
import '../theme.dart';
import '../utils/coords.dart';

/// 轨迹上的一個点：WGS-84 原始坐标 + 该点的瞬时倾角。
class RideMapPoint {
  const RideMapPoint({required this.lat, required this.lon, this.leanDeg = 0});

  final double lat;
  final double lon;
  final double leanDeg;
}

/// 基于腾讯地图 SDK 的轨迹地图。
///
/// GPS 记录的是 WGS-84，腾讯地图使用 GCJ-02，展示前统一做坐标转换，
/// 避免轨迹整体偏移几百米。
class RideMap extends StatefulWidget {
  const RideMap({
    super.key,
    required this.points,
    this.height = 200,
    this.colored = false,
    this.live = false,
    this.mapStyle = MapStyle.satellite,
    this.animateIn = false,
  });

  final List<RideMapPoint> points;
  final double height;
  final bool colored;
  final bool live;
  final MapStyle mapStyle;

  /// 非实时模式下，轨迹按时间轴从头绘制一遍（约 1 秒）。
  final bool animateIn;

  @override
  State<RideMap> createState() => _RideMapState();
}

class _RideMapState extends State<RideMap> with SingleTickerProviderStateMixin {
  TencentMapController? _controller;
  bool _mapReady = false;

  late final AnimationController _drawController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  )..addListener(() => setState(() {}));

  late final Animation<double> _drawProgress = CurvedAnimation(
    parent: _drawController,
    curve: AppMotion.curve,
  );

  @override
  void initState() {
    super.initState();
    if (widget.animateIn && widget.points.length > 1) {
      _drawController.forward();
    } else {
      _drawController.value = 1;
    }
  }

  @override
  void didUpdateWidget(covariant RideMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animateIn &&
        oldWidget.points.length < 2 &&
        widget.points.length > 1) {
      _drawController
        ..reset()
        ..forward();
    }
    if (widget.live && oldWidget.points.length != widget.points.length) {
      _followCurrent();
    }
  }

  @override
  void dispose() {
    _drawController.dispose();
    super.dispose();
  }

  LatLng _gcj(RideMapPoint point) {
    final (lat, lon) = GeoCoords.toGcj(lat: point.lat, lon: point.lon);
    return LatLng(lat, lon);
  }

  void _followCurrent() {
    final controller = _controller;
    if (controller == null || !_mapReady || widget.points.isEmpty) {
      return;
    }
    final target = _gcj(widget.points.last);
    controller.moveCamera(CameraUpdate.newLatLngZoom(target, 16));
  }

  void _fitBounds() {
    final controller = _controller;
    if (controller == null) {
      return;
    }
    if (widget.live || widget.points.length < 2) {
      return;
    }
    var minLat = 90.0, maxLat = -90.0, minLon = 180.0, maxLon = -180.0;
    for (final point in widget.points) {
      final gcj = _gcj(point);
      if (gcj.latitude < minLat) minLat = gcj.latitude;
      if (gcj.latitude > maxLat) maxLat = gcj.latitude;
      if (gcj.longitude < minLon) minLon = gcj.longitude;
      if (gcj.longitude > maxLon) maxLon = gcj.longitude;
    }
    controller.moveCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLon),
          northeast: LatLng(maxLat, maxLon),
        ),
        40,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.points.isEmpty) {
      return _StatusCard(
        height: widget.height,
        icon: Icons.route_outlined,
        title: '等待 GPS 轨迹…',
      );
    }

    if (!MapConfig.configured) {
      return _StatusCard(
        height: widget.height,
        icon: Icons.map_outlined,
        title: '地图未启用',
        hint: '需要腾讯地图 Key，编译时通过 --dart-define 传入',
      );
    }

    final allPoints = widget.points;
    final allLatLngs = [for (final p in allPoints) _gcj(p)];

    var visibleCount = allPoints.length;
    if (widget.animateIn &&
        !widget.live &&
        !AppMotion.reduced(context) &&
        allPoints.length > 1) {
      visibleCount = (1 + _drawProgress.value * (allPoints.length - 1))
          .ceil()
          .clamp(1, allPoints.length);
    }
    final visiblePoints = allPoints.sublist(0, visibleCount);
    final visibleLatLngs = allLatLngs.sublist(0, visibleCount);
    final drawComplete = visibleCount == allPoints.length;

    final polylines = widget.colored
        ? _coloredPolylines(visiblePoints, visibleLatLngs)
        : <Polyline>{
            if (visibleLatLngs.length > 1)
              Polyline(
                id: 'track',
                points: visibleLatLngs,
                width: 5,
                color: AppColors.accent,
              ),
          };

    final markers = <Marker>{
      if (!widget.live)
        Marker(
          id: 'start',
          position: allLatLngs.first,
          icon: BitmapDescriptor.fromAsset(
            'assets/map/marker_start.png',
            width: 22,
            height: 22,
          ),
          anchor: const Offset(0.5, 0.5),
        ),
      if (!widget.live && allLatLngs.length > 1 && drawComplete)
        Marker(
          id: 'end',
          position: allLatLngs.last,
          icon: BitmapDescriptor.fromAsset(
            'assets/map/marker_end.png',
            width: 22,
            height: 22,
          ),
          anchor: const Offset(0.5, 0.5),
        ),
      if (widget.live)
        Marker(
          id: 'current',
          position: allLatLngs.last,
          icon: BitmapDescriptor.fromAsset(
            'assets/map/marker_current.png',
            width: 24,
            height: 24,
          ),
          anchor: const Offset(0.5, 0.5),
        ),
    };

    return Container(
      height: widget.height,
      clipBehavior: Clip.antiAlias,
      decoration: cardDecoration(color: AppColors.surfaceHigh),
      child: Stack(
        children: [
          TencentMap(
            initialCameraPosition: CameraPosition(
              target: allLatLngs.last,
              zoom: widget.live ? 16 : 13,
            ),
            apiKey: TencentMapApiKey(
              iosKey: MapConfig.iosKey.isEmpty ? null : MapConfig.iosKey,
              androidKey: MapConfig.androidKey.isEmpty
                  ? null
                  : MapConfig.androidKey,
            ),
            mapType: switch (widget.mapStyle) {
              MapStyle.standard => MapType.normal,
              MapStyle.satellite => MapType.satellite,
              MapStyle.dark => MapType.dark,
            },
            compassEnabled: false,
            scaleEnabled: false,
            buildingsEnabled: false,
            rotateGesturesEnabled: false,
            tiltGesturesEnabled: false,
            markers: markers,
            polylines: polylines,
            onMapCreated: (controller) {
              _controller = controller;
              // onMapLoaded 在部分机型上触发较晚，补一次兜底取景。
              Future<void>.delayed(const Duration(milliseconds: 350), () {
                if (!mounted || _mapReady) {
                  return;
                }
                _mapReady = true;
                if (widget.live) {
                  _followCurrent();
                } else {
                  _fitBounds();
                }
              });
            },
            onMapLoaded: () {
              _mapReady = true;
              if (widget.live) {
                _followCurrent();
              } else {
                _fitBounds();
              }
            },
          ),
          // 只有实时记录页需要「回到当前位置」：用户拖动地图后可一键跟回。
          // 总结页的轨迹已经自动框住全图，再放一个按钮反而无反馈，故不显示。
          if (widget.live)
            Positioned(
              top: 8,
              right: 8,
              child: Material(
                color: Colors.white.withValues(alpha: 0.92),
                shape: const CircleBorder(),
                elevation: 2,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: _followCurrent,
                  child: const SizedBox(
                    width: 36,
                    height: 36,
                    child: Icon(
                      Icons.my_location_rounded,
                      size: 19,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            right: 8,
            bottom: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                '© 腾讯地图',
                style: TextStyle(fontSize: 11, color: Color(0xFFE8F1F4)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 按倾角区间把轨迹拆成多段，每段一条折线。
  Set<Polyline> _coloredPolylines(
    List<RideMapPoint> points,
    List<LatLng> latLngs,
  ) {
    if (latLngs.length < 2) {
      return const <Polyline>{};
    }
    final result = <Polyline>[];
    var color = leanColor(points[0].leanDeg);
    var segment = <LatLng>[latLngs[0]];
    for (var i = 1; i < latLngs.length; i++) {
      final nextColor = leanColor(points[i].leanDeg);
      segment.add(latLngs[i]);
      if (nextColor != color) {
        if (segment.length > 1) {
          result.add(
            Polyline(
              id: 'seg_${result.length}',
              points: List.of(segment),
              width: 5,
              color: color,
            ),
          );
        }
        segment = [latLngs[i]];
        color = nextColor;
      }
    }
    if (segment.length > 1) {
      result.add(
        Polyline(
          id: 'seg_${result.length}',
          points: segment,
          width: 5,
          color: color,
        ),
      );
    }
    return result.toSet();
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.height,
    required this.icon,
    required this.title,
    this.hint,
  });

  final double height;
  final IconData icon;
  final String title;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: cardDecoration(color: AppColors.surfaceHigh),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: AppColors.textTertiary, size: 28),
              const SizedBox(height: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textTertiary,
                ),
              ),
              if (hint != null) ...[
                const SizedBox(height: 4),
                Text(
                  hint!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 11,
                    height: 1.4,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 倾角越小越接近车漆的冷灰，越深越向品牌青、轮毂蓝过渡，
/// 超过 30° 才转入琥珀与红色警示区间。
Color leanColor(double leanDeg) {
  final lean = leanDeg.abs();
  if (lean >= 40) {
    return const Color(0xFFE8433A);
  }
  if (lean >= 30) {
    return const Color(0xFFF0A020);
  }
  if (lean >= 20) {
    return const Color(0xFF0F86C5);
  }
  if (lean >= 10) {
    return const Color(0xFF2ECBDC);
  }
  return const Color(0xFF9DB0B9);
}
