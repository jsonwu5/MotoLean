import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../services/settings_service.dart';
import '../theme.dart';

class RideMapPoint {
  const RideMapPoint({required this.lat, required this.lon, this.leanDeg = 0});

  final double lat;
  final double lon;
  final double leanDeg;
}

class RideMap extends StatefulWidget {
  const RideMap({
    super.key,
    required this.points,
    this.height = 200,
    this.colored = false,
    this.live = false,
    this.current,
    this.mapStyle = MapStyle.satellite,
    this.animateIn = false,
  });

  final List<RideMapPoint> points;
  final double height;
  final bool colored;
  final bool live;
  final LatLng? current;
  final MapStyle mapStyle;

  /// 非实时模式下，轨迹按时间轴从头绘制一遍（约 1 秒）。
  final bool animateIn;

  @override
  State<RideMap> createState() => _RideMapState();
}

class _RideMapState extends State<RideMap> with SingleTickerProviderStateMixin {
  final MapController _mapController = MapController();
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
    if (!widget.live) {
      return;
    }
    final oldLast = oldWidget.points.isEmpty ? null : oldWidget.points.last;
    final newLast = widget.points.isEmpty ? null : widget.points.last;
    final changed =
        oldLast == null ||
        newLast == null ||
        oldLast.lat != newLast.lat ||
        oldLast.lon != newLast.lon;
    if (changed) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _followCurrent());
    }
  }

  @override
  void dispose() {
    _drawController.dispose();
    super.dispose();
  }

  void _followCurrent() {
    if (!mounted || !_mapReady) {
      return;
    }
    final target =
        widget.current ??
        (widget.points.isEmpty
            ? null
            : LatLng(widget.points.last.lat, widget.points.last.lon));
    if (target == null) {
      return;
    }
    try {
      _mapController.move(target, 16);
    } catch (_) {
      // The controller can be briefly unavailable during route transitions.
    }
  }

  @override
  Widget build(BuildContext context) {
    final points = widget.points;
    if (points.isEmpty) {
      return Container(
        height: widget.height,
        decoration: cardDecoration(color: AppColors.surfaceHigh),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.route_outlined,
                color: AppColors.textTertiary,
                size: 28,
              ),
              SizedBox(height: 8),
              Text(
                '等待 GPS 轨迹…',
                style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
              ),
            ],
          ),
        ),
      );
    }

    // 取景始终基于全量轨迹；绘制层按动画进度截断。
    final fullLatLngs = [for (final p in points) LatLng(p.lat, p.lon)];
    var visiblePoints = points;
    if (widget.animateIn &&
        !widget.live &&
        !AppMotion.reduced(context) &&
        points.length > 1) {
      final count = (1 + _drawProgress.value * (points.length - 1))
          .ceil()
          .clamp(1, points.length);
      visiblePoints = points.sublist(0, count);
    }
    final latLngs = [for (final p in visiblePoints) LatLng(p.lat, p.lon)];
    final drawComplete = visiblePoints.length == points.length;
    final current =
        widget.current ??
        (widget.live ? LatLng(points.last.lat, points.last.lon) : null);
    final showFit = !widget.live && fullLatLngs.length > 1;

    final options = MapOptions(
      initialCenter: current ?? fullLatLngs.last,
      initialZoom: widget.live ? 16 : 13,
      initialCameraFit: showFit
          ? CameraFit.bounds(
              bounds: LatLngBounds.fromPoints(fullLatLngs),
              padding: const EdgeInsets.all(30),
            )
          : null,
      minZoom: 3,
      maxZoom: 18,
      backgroundColor: AppColors.surfaceHigh,
      interactionOptions: const InteractionOptions(
        flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
      ),
      onMapReady: () {
        _mapReady = true;
        if (widget.live) {
          _followCurrent();
        }
      },
    );

    return Container(
      height: widget.height,
      clipBehavior: Clip.antiAlias,
      decoration: cardDecoration(color: AppColors.surfaceHigh),
      child: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: options,
            children: [
              TileLayer(
                urlTemplate: widget.mapStyle == MapStyle.dark
                    ? 'https://basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png'
                    : 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
                userAgentPackageName: 'com.jsonwoo.motolean',
              ),
              if (widget.colored)
                PolylineLayer(polylines: _coloredPolylines(visiblePoints))
              else
                PolylineLayer(
                  polylines: [
                    if (latLngs.length > 1)
                      Polyline(
                        points: latLngs,
                        strokeWidth: 5,
                        color: AppColors.accent,
                        strokeCap: StrokeCap.round,
                      ),
                  ],
                ),
              MarkerLayer(
                markers: [
                  if (!widget.live) _startMarker(fullLatLngs.first),
                  if (!widget.live && fullLatLngs.length > 1 && drawComplete)
                    _endMarker(fullLatLngs.last),
                  if (widget.live)
                    Marker(
                      point: current!,
                      width: 24,
                      height: 24,
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.accent,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.accent.withValues(alpha: 0.45),
                              blurRadius: 14,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          Positioned(
            right: 8,
            bottom: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                widget.mapStyle == MapStyle.dark
                    ? '© OpenStreetMap · CARTO'
                    : '© Esri · Maxar · Earthstar Geographics',
                style: const TextStyle(
                  fontSize: 8,
                  color: Color(0xFFDCE6EA),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Marker _startMarker(LatLng point) => Marker(
    point: point,
    width: 26,
    height: 26,
    child: Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.accent, width: 2.5),
      ),
      child: const Center(
        child: Text(
          '起',
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: AppColors.accentInk,
          ),
        ),
      ),
    ),
  );

  Marker _endMarker(LatLng point) => Marker(
    point: point,
    width: 26,
    height: 26,
    child: Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.danger, width: 2.5),
      ),
      child: const Center(
        child: Text(
          '终',
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: AppColors.danger,
          ),
        ),
      ),
    ),
  );

  List<Polyline> _coloredPolylines(List<RideMapPoint> visible) {
    if (visible.length < 2) {
      return [];
    }
    final latLngs = [for (final p in visible) LatLng(p.lat, p.lon)];
    final result = <Polyline>[];
    var color = leanColor(visible[0].leanDeg);
    var segment = <LatLng>[latLngs[0]];
    for (var i = 1; i < latLngs.length; i++) {
      final nextColor = leanColor(visible[i].leanDeg);
      segment.add(latLngs[i]);
      if (nextColor != color) {
        if (segment.length > 1) {
          result.add(
            Polyline(
              points: List.of(segment),
              strokeWidth: 5,
              color: color,
              strokeCap: StrokeCap.round,
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
          points: segment,
          strokeWidth: 5,
          color: color,
          strokeCap: StrokeCap.round,
        ),
      );
    }
    return result;
  }
}

Color leanColor(double leanDeg) {
  final lean = leanDeg.abs();
  if (lean >= 40) {
    return AppColors.danger;
  }
  if (lean >= 30) {
    return AppColors.orange;
  }
  if (lean >= 20) {
    return AppColors.amber;
  }
  if (lean >= 10) {
    return AppColors.accent;
  }
  return AppColors.textTertiary;
}
