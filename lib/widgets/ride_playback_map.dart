import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tencent_map/flutter_tencent_map.dart';

import '../config/map_config.dart';
import '../models/ride_sample.dart';
import '../services/settings_service.dart';
import '../theme.dart';
import '../utils/coords.dart';
import '../utils/format.dart';
import '../utils/units.dart';
import 'ride_map.dart' show leanColor;

/// 轨迹上的一个可播放点（已剔除没有定位的采样）。
class PlaybackPoint {
  PlaybackPoint({
    required this.tMs,
    required this.lat,
    required this.lon,
    required this.leanDeg,
    this.speedMps,
    this.altitudeM,
  });

  final int tMs;
  final double lat;
  final double lon;
  final double leanDeg;
  final double? speedMps;
  final double? altitudeM;

  /// GCJ-02 坐标惰性计算一次，避免每帧重复转换。
  late final double gcjLat = GeoCoords.toGcj(lat: lat, lon: lon).$1;
  late final double gcjLon = GeoCoords.toGcj(lat: lat, lon: lon).$2;
}

/// 把 1 Hz 的采样整理成可播放的轨迹点。
List<PlaybackPoint> buildPlaybackPoints(List<RideSample> samples) {
  final points = <PlaybackPoint>[];
  for (final sample in samples) {
    final lat = sample.lat;
    final lon = sample.lon;
    if (lat == null || lon == null) {
      continue;
    }
    points.add(
      PlaybackPoint(
        tMs: sample.tMs,
        lat: lat,
        lon: lon,
        leanDeg: sample.leanDeg,
        speedMps: sample.speedMps,
        altitudeM: sample.altitudeM,
      ),
    );
  }
  points.sort((a, b) => a.tMs.compareTo(b.tMs));
  return points;
}

/// 全屏轨迹回放：地图铺满，HUD 浮在底部。
class RidePlaybackMap extends StatefulWidget {
  const RidePlaybackMap({
    super.key,
    required this.points,
    this.initialStyle = MapStyle.standard,
    this.speedUnit = SpeedUnit.kmh,
    this.bottomInset = 0,
    this.topInset = 0,
  });

  final List<PlaybackPoint> points;
  final MapStyle initialStyle;
  final SpeedUnit speedUnit;

  /// 供外层留出安全区与顶部按钮的空间。
  final double bottomInset;
  final double topInset;

  @override
  State<RidePlaybackMap> createState() => _RidePlaybackMapState();
}

class _RidePlaybackMapState extends State<RidePlaybackMap>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  TencentMapController? _controller;
  bool _mapReady = false;

  Duration _lastTick = Duration.zero;
  Duration _lastCameraMove = Duration.zero;

  double _positionMs = 0;
  double _pendingMs = 0;
  double _speedFactor = 1;
  bool _playing = false;
  bool _follow = true;
  bool _tilt = false;
  late MapStyle _style = widget.initialStyle;

  int _traveledBucket = -1;
  Set<Polyline>? _traveled;
  Set<Polyline>? _remaining;

  List<PlaybackPoint> get _points => widget.points;
  int get _totalMs => _points.isEmpty ? 0 : _points.last.tMs;

  int get _currentIndex {
    if (_points.isEmpty) {
      return 0;
    }
    var low = 0;
    var high = _points.length - 1;
    while (low < high) {
      final mid = (low + high + 1) >> 1;
      if (_points[mid].tMs <= _positionMs) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }
    return low;
  }

  double get _progress =>
      _totalMs <= 0 ? 0 : (_positionMs / _totalMs).clamp(0.0, 1.0);

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    if (!_playing || _totalMs <= 0) {
      _lastTick = elapsed;
      return;
    }
    final deltaMs =
        (elapsed - _lastTick).inMicroseconds / 1000.0 * _speedFactor;
    _lastTick = elapsed;
    if (deltaMs <= 0) {
      return;
    }
    // 合并高频 tick，约 25fps 刷新一次，减少原生地图的通道调用。
    _pendingMs += deltaMs;
    if (_pendingMs < 40) {
      return;
    }
    var next = _positionMs + _pendingMs;
    _pendingMs = 0;
    if (next >= _totalMs) {
      next = _totalMs.toDouble();
      _playing = false;
      _ticker.stop();
      HapticFeedback.mediumImpact();
    }
    setState(() => _positionMs = next);
    _maybeMoveCamera(elapsed);
  }

  void _maybeMoveCamera(Duration elapsed) {
    if (!_follow || !_mapReady) {
      return;
    }
    if (elapsed - _lastCameraMove < const Duration(milliseconds: 450)) {
      return;
    }
    _lastCameraMove = elapsed;
    final position = _currentLatLng;
    if (position == null) {
      return;
    }
    _controller?.moveCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: position,
          zoom: _tilt ? 17 : 16.5,
          tilt: _tilt ? 50 : 0,
        ),
      ),
    );
  }

  void _togglePlay() {
    if (_totalMs <= 0) {
      return;
    }
    HapticFeedback.selectionClick();
    setState(() {
      if (!_playing && _positionMs >= _totalMs) {
        _positionMs = 0;
      }
      _playing = !_playing;
    });
    if (_playing) {
      _lastTick = Duration.zero;
      _ticker.start();
    } else {
      _ticker.stop();
    }
  }

  void _seek(double progress) {
    setState(() {
      _positionMs = progress.clamp(0.0, 1.0) * _totalMs;
      _traveledBucket = -1;
    });
    if (_playing) {
      _ticker.stop();
      _lastTick = Duration.zero;
      _ticker.start();
    }
  }

  void _cycleSpeed() {
    HapticFeedback.selectionClick();
    setState(() {
      _speedFactor = switch (_speedFactor) {
        1 => 2,
        2 => 4,
        _ => 1,
      };
    });
  }

  /// 立即把当前视角参数（含 3D 倾斜）下发到原生地图。
  /// 暂停状态下也必须调用，否则切换 3D 看不到任何变化。
  void _applyCamera() {
    final controller = _controller;
    final position = _currentLatLng;
    if (controller == null || position == null) {
      return;
    }
    _lastCameraMove = Duration.zero;
    controller.moveCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: position,
          zoom: _tilt ? 17 : 16.5,
          tilt: _tilt ? 55 : 0,
        ),
      ),
    );
  }

  void _fitAll() {
    if (_controller == null || _points.length < 2) {
      return;
    }
    if (_tilt) {
      setState(() => _tilt = false);
    }
    var minLat = 90.0, maxLat = -90.0, minLon = 180.0, maxLon = -180.0;
    for (final point in _points) {
      minLat = math.min(minLat, point.gcjLat);
      maxLat = math.max(maxLat, point.gcjLat);
      minLon = math.min(minLon, point.gcjLon);
      maxLon = math.max(maxLon, point.gcjLon);
    }
    _controller?.moveCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLon),
          northeast: LatLng(maxLat, maxLon),
        ),
        64,
      ),
    );
  }

  LatLng? get _currentLatLng {
    if (_points.isEmpty) {
      return null;
    }
    final index = _currentIndex;
    final current = _points[index];
    if (index >= _points.length - 1) {
      return LatLng(current.gcjLat, current.gcjLon);
    }
    final next = _points[index + 1];
    final span = next.tMs - current.tMs;
    final f = span <= 0
        ? 0.0
        : ((_positionMs - current.tMs) / span).clamp(0.0, 1.0);
    return LatLng(
      current.gcjLat + (next.gcjLat - current.gcjLat) * f,
      current.gcjLon + (next.gcjLon - current.gcjLon) * f,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_points.length < 2) {
      return Container(
        color: AppColors.surfaceHigh,
        alignment: Alignment.center,
        child: const Text(
          '这次行程没有可回放的轨迹',
          style: TextStyle(fontSize: 13, color: AppColors.textTertiary),
        ),
      );
    }

    if (!MapConfig.configured) {
      return Container(
        color: AppColors.surfaceHigh,
        alignment: Alignment.center,
        child: const Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            '需要腾讯地图 Key 才能回放轨迹',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppColors.textTertiary),
          ),
        ),
      );
    }

    final current = _points[_currentIndex];
    final latLng = _currentLatLng;

    return Stack(
      fit: StackFit.expand,
      children: [
        TencentMap(
          initialCameraPosition: CameraPosition(
            target: LatLng(_points.first.gcjLat, _points.first.gcjLon),
            zoom: 15,
          ),
          apiKey: TencentMapApiKey(
            iosKey: MapConfig.iosKey.isEmpty ? null : MapConfig.iosKey,
            androidKey:
                MapConfig.androidKey.isEmpty ? null : MapConfig.androidKey,
          ),
          mapType: switch (_style) {
            MapStyle.standard => MapType.normal,
            MapStyle.satellite => MapType.satellite,
            MapStyle.dark => MapType.dark,
          },
          compassEnabled: false,
          scaleEnabled: false,
          buildingsEnabled: false,
          rotateGesturesEnabled: false,
          tiltGesturesEnabled: false,
          polylines: {
            ...?_remainingPolylines(),
            ...?_traveledPolylines(),
          },
          markers: {
            if (latLng != null)
              Marker(
                id: 'rider',
                position: latLng,
                icon: BitmapDescriptor.fromAsset(
                  'assets/map/marker_rider.png',
                  width: 46,
                  height: 46,
                ),
                anchor: const Offset(0.5, 0.5),
                zIndex: 10,
              ),
          },
          onMapCreated: (controller) {
            _controller = controller;
            Future<void>.delayed(const Duration(milliseconds: 350), () {
              if (!mounted || _mapReady) {
                return;
              }
              _mapReady = true;
              _fitAll();
            });
          },
          onMapLoaded: () {
            _mapReady = true;
            _fitAll();
          },
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: widget.topInset + 120,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.48),
                    Colors.black.withValues(alpha: 0.16),
                    Colors.black.withValues(alpha: 0),
                  ],
                  stops: const [0, 0.55, 1],
                ),
              ),
            ),
          ),
        ),
        Positioned(top: widget.topInset + 16, right: 14, child: _mapActions()),
        Positioned(left: 0, right: 0, bottom: 0, child: _hud(current)),
      ],
    );
  }

  Widget _mapActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _StyleSegments(
          value: _style,
          onChanged: (style) {
            HapticFeedback.selectionClick();
            setState(() {
              _style = style;
              _remaining = null;
            });
          },
        ),
      ],
    );
  }

  Widget _hud(PlaybackPoint current) {
    final speed = current.speedMps;
    final speedText =
        speed == null ? '--' : formatSpeedValue(speed, widget.speedUnit);

    return Container(
      padding: EdgeInsets.fromLTRB(14, 26, 14, 14 + widget.bottomInset),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0),
            Colors.black.withValues(alpha: 0.34),
            Colors.black.withValues(alpha: 0.58),
          ],
          stops: const [0, 0.32, 1],
        ),
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: Colors.white.withValues(alpha: 0.65)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.20),
              blurRadius: 26,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '当前速度',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textTertiary,
                      ),
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          speedText,
                          style: const TextStyle(
                            fontSize: 42,
                            height: 1,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -2,
                            color: AppColors.textPrimary,
                            fontFeatures: tabularFigures,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 5),
                          child: Text(
                            widget.speedUnit.label,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const Spacer(),
                _LeanBadge(degrees: current.leanDeg),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _MiniStat(
                      label: '时间',
                      value: formatDuration((_positionMs / 1000).round()),
                    ),
                    const SizedBox(height: 6),
                    _MiniStat(
                      label: '海拔',
                      value: current.altitudeM == null
                          ? '--'
                          : '${current.altitudeM!.round()} m',
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 4),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 4,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
                activeTrackColor: AppColors.accent,
                inactiveTrackColor: AppColors.surfaceHighest,
                thumbColor: Colors.white,
                overlayColor: AppColors.accent.withValues(alpha: 0.16),
              ),
              child: Slider(value: _progress, onChanged: _seek),
            ),
            Row(
              children: [
                Material(
                  color: AppColors.accent,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: _togglePlay,
                    child: SizedBox(
                      width: 50,
                      height: 50,
                      child: Icon(
                        _playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 30,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _PillButton(
                  label: '${_speedFactor.toStringAsFixed(0)}×',
                  onTap: _cycleSpeed,
                ),
                const Spacer(),
                _ToggleButton(
                  icon: Icons.my_location_rounded,
                  label: '跟随',
                  active: _follow,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _follow = !_follow);
                    if (_follow) {
                      _applyCamera();
                    }
                  },
                ),
                const SizedBox(width: 8),
                _ToggleButton(
                  icon: Icons.threed_rotation_rounded,
                  label: '3D',
                  active: _tilt,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _tilt = !_tilt);
                    _applyCamera();
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Set<Polyline>? _remainingPolylines() {
    if (_remaining != null) {
      return _remaining;
    }
    final result = <Polyline>[];
    var color = leanColor(_points[0].leanDeg);
    var segment = <LatLng>[LatLng(_points[0].gcjLat, _points[0].gcjLon)];
    void flush() {
      if (segment.length > 1) {
        result.add(
          Polyline(
            id: 'rest_${result.length}',
            points: List.of(segment),
            width: 3.5,
            color: color.withValues(alpha: 0.38),
          ),
        );
      }
    }

    for (var i = 1; i < _points.length; i++) {
      final p = _points[i];
      final nextColor = leanColor(p.leanDeg);
      segment.add(LatLng(p.gcjLat, p.gcjLon));
      if (nextColor != color) {
        flush();
        segment = [LatLng(p.gcjLat, p.gcjLon)];
        color = nextColor;
      }
    }
    flush();
    _remaining = result.toSet();
    return _remaining;
  }

  Set<Polyline>? _traveledPolylines() {
    final bucket = _currentIndex ~/ 4;
    if (_traveled != null && bucket == _traveledBucket) {
      return _traveled;
    }
    _traveledBucket = bucket;
    final end = math.min(_currentIndex + 1, _points.length);
    if (end < 2) {
      _traveled = const <Polyline>{};
      return _traveled;
    }
    final result = <Polyline>[];
    var color = leanColor(_points[0].leanDeg);
    var segment = <LatLng>[LatLng(_points[0].gcjLat, _points[0].gcjLon)];
    void flush() {
      if (segment.length > 1) {
        result.add(
          Polyline(
            id: 'done_${result.length}',
            points: List.of(segment),
            width: 6,
            color: color,
          ),
        );
      }
    }

    for (var i = 1; i < end; i++) {
      final p = _points[i];
      final nextColor = leanColor(p.leanDeg);
      segment.add(LatLng(p.gcjLat, p.gcjLon));
      if (nextColor != color) {
        flush();
        segment = [LatLng(p.gcjLat, p.gcjLon)];
        color = nextColor;
      }
    }
    flush();
    _traveled = result.toSet();
    return _traveled;
  }
}

class _LeanBadge extends StatelessWidget {
  const _LeanBadge({required this.degrees});

  final double degrees;

  @override
  Widget build(BuildContext context) {
    final leaning = degrees.abs() >= 1;
    final color = leaning ? leanColor(degrees) : AppColors.textTertiary;
    final direction = degrees > 0 ? '右倾' : (degrees < 0 ? '左倾' : '直立');
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Text(
            '${degrees.abs().round()}°',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: color,
              fontFeatures: tabularFigures,
            ),
          ),
        ),
        const SizedBox(height: 3),
        Text(
          direction,
          style: const TextStyle(fontSize: 10, color: AppColors.textTertiary),
        ),
      ],
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: AppColors.textTertiary),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
            fontFeatures: tabularFigures,
          ),
        ),
      ],
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceHigh,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _ToggleButton extends StatelessWidget {
  const _ToggleButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.accent : AppColors.textSecondary;
    return Material(
      color: active
          ? AppColors.accent.withValues(alpha: 0.14)
          : AppColors.surfaceHigh,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StyleSegments extends StatelessWidget {
  const _StyleSegments({required this.value, required this.onChanged});

  final MapStyle value;
  final ValueChanged<MapStyle> onChanged;

  static const _items = <(MapStyle, String)>[
    (MapStyle.standard, '标准'),
    (MapStyle.satellite, '卫星'),
    (MapStyle.dark, '暗色'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final item in _items)
            GestureDetector(
              onTap: () => onChanged(item.$1),
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: AppMotion.fast,
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                decoration: BoxDecoration(
                  color: value == item.$1 ? AppColors.accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(17),
                ),
                child: Text(
                  item.$2,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: value == item.$1
                        ? Colors.white
                        : AppColors.textSecondary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

