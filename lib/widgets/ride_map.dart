import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../theme.dart';

class RideMapPoint {
  const RideMapPoint({
    required this.lat,
    required this.lon,
    this.leanDeg = 0,
  });

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
  });

  final List<RideMapPoint> points;
  final double height;
  final bool colored;
  final bool live;
  final LatLng? current;

  @override
  State<RideMap> createState() => _RideMapState();
}

class _RideMapState extends State<RideMap> {
  final MapController _mapController = MapController();
  bool _mapReady = false;

  @override
  void didUpdateWidget(covariant RideMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.live) {
      return;
    }
    final oldLast = oldWidget.points.isEmpty ? null : oldWidget.points.last;
    final newLast = widget.points.isEmpty ? null : widget.points.last;
    final changed = oldLast == null ||
        newLast == null ||
        oldLast.lat != newLast.lat ||
        oldLast.lon != newLast.lon;
    if (changed) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _followCurrent());
    }
  }

  void _followCurrent() {
    if (!mounted || !_mapReady) {
      return;
    }
    final target = widget.current ??
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
              Icon(Icons.route_outlined, color: AppColors.textTertiary, size: 28),
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

    final latLngs = [for (final p in points) LatLng(p.lat, p.lon)];
    final current = widget.current ??
        (widget.live ? LatLng(points.last.lat, points.last.lon) : null);
    final showFit = !widget.live && latLngs.length > 1;

    final options = MapOptions(
      initialCenter: current ?? latLngs.last,
      initialZoom: widget.live ? 16 : 13,
      initialCameraFit: showFit
          ? CameraFit.bounds(
              bounds: LatLngBounds.fromPoints(latLngs),
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
                urlTemplate:
                    'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
                userAgentPackageName: 'com.jsonwoo.motolean',
              ),
              if (widget.colored)
                PolylineLayer(
                  polylines: _coloredPolylines(latLngs),
                )
              else
                PolylineLayer(
                  polylines: [
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
                  if (!widget.live)
                    _startMarker(latLngs.first),
                  if (!widget.live && latLngs.length > 1)
                    _endMarker(latLngs.last),
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
              child: const Text(
                '© Esri · Maxar · Earthstar Geographics',
                style: TextStyle(fontSize: 8, color: AppColors.textSecondary),
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
                color: AppColors.accent,
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

  List<Polyline> _coloredPolylines(List<LatLng> latLngs) {
    if (latLngs.length < 2) {
      return [];
    }
    final result = <Polyline>[];
    var color = leanColor(widget.points[0].leanDeg);
    var segment = <LatLng>[latLngs[0]];
    for (var i = 1; i < latLngs.length; i++) {
      final nextColor = leanColor(widget.points[i].leanDeg);
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
  return const Color(0xFF56606D);
}
