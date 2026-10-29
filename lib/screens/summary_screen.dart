import 'dart:convert';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../models/ride_sample.dart';
import '../models/ride_session.dart';
import '../services/ride_exporter.dart';
import '../services/ride_store.dart';
import '../services/settings_service.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../utils/ride_analytics.dart';
import '../utils/units.dart';
import '../widgets/motion.dart';
import '../widgets/ride_map.dart';
import '../services/share_image.dart';
import '../widgets/share_poster.dart';
import 'track_playback_screen.dart';
import '../widgets/stat_tile.dart';

class SummaryScreen extends StatefulWidget {
  const SummaryScreen({
    super.key,
    required this.store,
    required this.settings,
    required this.sessionId,
  });

  final RideStore store;
  final SettingsService settings;
  final int sessionId;

  @override
  State<SummaryScreen> createState() => _SummaryScreenState();
}

class _SummaryScreenState extends State<SummaryScreen> {
  RideSession? _session;
  List<RideSample> _samples = const [];
  bool _loading = true;
  bool _exporting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final session = await widget.store.loadSession(widget.sessionId);
      final samples = session == null
          ? <RideSample>[]
          : await widget.store.loadSamples(widget.sessionId);
      if (!mounted) {
        return;
      }
      setState(() {
        _session = session;
        _samples = samples;
        _loading = false;
        _error = session == null ? '找不到这次行程，可能已经被删除。' : null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = '读取行程失败：$error';
      });
    }
  }

  void _openPlayback() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TrackPlaybackScreen(
          samples: _samples,
          settings: widget.settings,
          subtitle: _session == null
              ? null
              : formatDateWithWeekday(_session!.startedAt),
        ),
      ),
    );
  }

  Future<void> _sharePoster() async {
    final session = _session;
    if (session == null) {
      return;
    }
    final caption = [
      '摩倾 · ${formatDateWithWeekday(session.startedAt)}',
      '里程 ${formatDistanceWithUnit(session.distanceM, widget.settings.distanceUnit)}'
          ' · 最大右倾 ${session.maxLeanRightDeg.round()}°'
          ' · 最大左倾 ${session.maxLeanLeftDeg.round()}°',
    ].join('\n');

    final saved = await showSharePosterDialog(
      context,
      poster: RideSharePoster(
        session: session,
        bands: RideAnalytics.leanBands(_samples),
        corners: RideAnalytics.cornerCount(_samples),
        settings: widget.settings,
      ),
      fileName: 'motolean_ride_${formatFileStamp(session.startedAt)}.png',
      subject: '摩倾骑行总结',
      text: caption,
    );

    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('长图已保存到相册，可去微信 / 抖音选图发布'),
          action: SnackBarAction(
            label: '打开相册',
            onPressed: () => ShareImage.openGallery(),
          ),
        ),
      );
    }
  }

  Future<void> _export({required bool gpx}) async {
    final session = _session;
    if (session == null || _exporting) {
      return;
    }
    setState(() => _exporting = true);
    try {
      final content = gpx
          ? RideExporter.buildGpx(session, _samples)
          : RideExporter.buildCsv(session, _samples);
      final extension = gpx ? 'gpx' : 'csv';
      final file = XFile.fromData(
        utf8.encode(content),
        mimeType: gpx ? 'application/gpx+xml' : 'text/csv',
        name: 'motolean_${formatFileStamp(session.startedAt)}.$extension',
      );
      await SharePlus.instance.share(
        ShareParams(
          files: [file],
          subject: '摩倾骑行数据',
          text: '摩倾 · ${formatDateWithWeekday(session.startedAt)}',
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('导出失败：$error')));
      }
    } finally {
      if (mounted) {
        setState(() => _exporting = false);
      }
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这次行程？'),
        content: const Text('本地轨迹与统计数据将被永久删除，无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 44),
              padding: const EdgeInsets.symmetric(horizontal: 18),
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    try {
      await widget.store.deleteSession(widget.sessionId);
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('删除失败：$error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('行程总结'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_horiz_rounded),
            color: AppColors.surfaceHigh,
            onSelected: (value) {
              switch (value) {
                case 'gpx':
                  _export(gpx: true);
                  break;
                case 'csv':
                  _export(gpx: false);
                  break;
                case 'delete':
                  _delete();
                  break;
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'gpx', child: Text('导出 GPX')),
              PopupMenuItem(value: 'csv', child: Text('导出 CSV')),
              PopupMenuItem(
                value: 'delete',
                child: Text('删除行程', style: TextStyle(color: AppColors.danger)),
              ),
            ],
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: _loading
          ? _buildLoadingShell()
          : _error != null || _session == null
          ? _ErrorView(message: _error ?? '未知错误', onRetry: _load)
          : _buildContent(_session!),
    );
  }

  /// 加载中的骨架：地图区域首帧就位，保证首页卡片的 Hero 过渡有落点。
  Widget _buildLoadingShell() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
      children: [
        const SizedBox(height: 40),
        _wrapMapHero(
          Container(
            height: 250,
            decoration: cardDecoration(color: AppColors.surfaceHigh),
          ),
        ),
        const SizedBox(height: 36),
        const Center(
          child: SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ],
    );
  }

  /// 首页行程卡片 → 总结页地图的共享元素过渡；减弱动效时退化为普通容器。
  Widget _wrapMapHero(Widget child) {
    if (AppMotion.reduced(context)) {
      return child;
    }
    return Hero(tag: 'session-hero-${widget.sessionId}', child: child);
  }

  Widget _buildContent(RideSession session) {
    final bands = RideAnalytics.leanBands(_samples);
    final corners = RideAnalytics.cornerCount(_samples);
    final above30 = RideAnalytics.secondsAboveLean(_samples, 30);
    final unit = widget.settings.speedUnit;
    final distanceUnit = widget.settings.distanceUnit;
    final elevationUnit = widget.settings.elevationUnit;
    final mapPoints = [
      for (final sample in _samples)
        if (sample.hasPosition)
          RideMapPoint(
            lat: sample.lat!,
            lon: sample.lon!,
            leanDeg: sample.leanDeg,
          ),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
      children: [
        StaggerIn(
          index: 0,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      formatDateWithWeekday(session.startedAt),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textTertiary,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Text(
                          '本次骑行',
                          style: TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -1,
                          ),
                        ),
                        if (session.isDemo) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.accentSoft,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              '演示',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppColors.accentInk,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatClock(session.startedAt),
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                      fontFeatures: tabularFigures,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    formatDuration(session.durationS),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      fontFeatures: tabularFigures,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (session.isDemo && session.note != null) ...[
          const SizedBox(height: 8),
          Text(
            session.note!,
            style: const TextStyle(fontSize: 11.5, color: AppColors.textTertiary),
          ),
        ],
        const SizedBox(height: 18),
        StaggerIn(
          index: 1,
          child: _wrapMapHero(
            RemoteMapCard(
              points: mapPoints,
              hasTrack: mapPoints.length > 1,
              mapStyle: widget.settings.mapStyle,
              onPlay: () => _openPlayback(),
            ),
          ),
        ),
        const SizedBox(height: 20),
        StaggerIn(
          index: 2,
          child: Row(
            children: [
              Expanded(
                child: StatTile(
                  label: '最大右倾',
                  value: session.maxLeanRightDeg > 0
                      ? '${session.maxLeanRightDeg.round()}°'
                      : '—',
                  accent: true,
                  countUp: session.maxLeanRightDeg > 0
                      ? session.maxLeanRightDeg
                      : null,
                  countFormat: (v) => '${v.round()}°',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: StatTile(
                  label: '最大左倾',
                  value: session.maxLeanLeftDeg > 0
                      ? '${session.maxLeanLeftDeg.round()}°'
                      : '—',
                  countUp: session.maxLeanLeftDeg > 0
                      ? session.maxLeanLeftDeg
                      : null,
                  countFormat: (v) => '${v.round()}°',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        StaggerIn(
          index: 3,
          child: Row(
            children: [
              Expanded(
                child: StatTile(
                  label: '里程',
                  value: formatDistanceWithUnit(
                    session.distanceM,
                    distanceUnit,
                  ),
                  countUp: session.distanceM,
                  countFormat: (v) => formatDistanceWithUnit(v, distanceUnit),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: StatTile(
                  label: '骑行时长',
                  value: formatDuration(session.durationS),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        StaggerIn(
          index: 4,
          child: Row(
            children: [
              Expanded(
                child: StatTile(
                  label: '均速',
                  value: formatSpeedValue(session.avgSpeedMps, unit),
                  unit: unit.label,
                  countUp: session.avgSpeedMps,
                  countFormat: (v) => formatSpeedValue(v, unit),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: StatTile(
                  label: '极速',
                  value: formatSpeedValue(session.maxSpeedMps, unit),
                  unit: unit.label,
                  countUp: session.maxSpeedMps,
                  countFormat: (v) => formatSpeedValue(v, unit),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        StaggerIn(
          index: 5,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _HighlightChip(
                icon: Icons.turn_right_rounded,
                label: '过弯',
                value: '$corners 次',
              ),
              _HighlightChip(
                icon: Icons.speed_rounded,
                label: '超 30°',
                value: formatDuration(above30),
              ),
              _HighlightChip(
                icon: Icons.terrain_rounded,
                label: '爬升',
                value: formatElevationWithUnit(
                  session.elevationGainM,
                  elevationUnit,
                ),
              ),
              _HighlightChip(
                icon: Icons.timeline_rounded,
                label: '采样',
                value: '${_samples.length} 秒',
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        StaggerIn(
          index: 6,
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: cardDecoration(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '倾角分布',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                const Text(
                  '占记录时长比例（1 Hz 采样）',
                  style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
                ),
                const SizedBox(height: 18),
                _LeanBands(bands: bands),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        StaggerIn(
          index: 7,
          child: Container(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
            decoration: cardDecoration(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '速度曲线',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  'GPS 速度 · ${unit.label}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textTertiary,
                  ),
                ),
                const SizedBox(height: 16),
                _SpeedChart(
                  points: RideAnalytics.speedSeries(_samples),
                  unit: unit,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        StaggerIn(
          index: 8,
          child: FilledButton.icon(
            onPressed: _exporting ? null : _sharePoster,
            icon: const Icon(Icons.ios_share_rounded, size: 20),
            label: const Text('保存长图'),
          ),
        ),
        const SizedBox(height: 10),
        StaggerIn(
          index: 8,
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _exporting ? null : () => _export(gpx: true),
                  icon: const Icon(Icons.file_download_outlined, size: 18),
                  label: const Text('导出 GPX'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _exporting ? null : () => _export(gpx: false),
                  icon: const Icon(Icons.table_chart_outlined, size: 18),
                  label: const Text('导出 CSV'),
                ),
              ),
            ],
          ),
        ),
        if (_exporting) ...[
          const SizedBox(height: 10),
          const Center(
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ],
        const SizedBox(height: 12),
        Center(
          child: TextButton.icon(
            onPressed: _exporting ? null : _delete,
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
            label: const Text('删除这次行程'),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textTertiary,
            ),
          ),
        ),
      ],
    );
  }
}

class RemoteMapCard extends StatelessWidget {
  const RemoteMapCard({
    super.key,
    required this.points,
    required this.hasTrack,
    this.mapStyle = MapStyle.satellite,
    this.onPlay,
  });

  final List<RideMapPoint> points;
  final bool hasTrack;
  final MapStyle mapStyle;
  final VoidCallback? onPlay;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasTrack)
          Stack(
            children: [
              RideMap(
                points: points,
                height: 250,
                colored: true,
                mapStyle: mapStyle,
                animateIn: true,
              ),
              if (onPlay != null)
                Positioned(
                  left: 12,
                  bottom: 12,
                  child: Material(
                    color: const Color(0xD90C191E),
                    borderRadius: BorderRadius.circular(28),
                    elevation: 8,
                    shadowColor: Colors.black.withValues(alpha: 0.45),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(28),
                      onTap: onPlay,
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(5, 5, 17, 5),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.16),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 30,
                              height: 30,
                              decoration: const BoxDecoration(
                                color: AppColors.accent,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.play_arrow_rounded,
                                size: 20,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 9),
                            const Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '回放轨迹',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    height: 1.1,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.2,
                                    color: Colors.white,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  '按时间重现这一趟',
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    height: 1.1,
                                    color: Color(0xB3FFFFFF),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          )
        else
          Container(
            height: 140,
            width: double.infinity,
            decoration: cardDecoration(color: AppColors.surfaceHigh),
            child: const Center(
              child: Text(
                '本次行程没有可用的 GPS 轨迹',
                style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
              ),
            ),
          ),
        if (hasTrack) ...[
          const SizedBox(height: 10),
          const Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              _LegendItem(color: AppColors.textTertiary, label: '0–10°'),
              _LegendItem(color: AppColors.accent, label: '10–20°'),
              _LegendItem(color: AppColors.amber, label: '20–30°'),
              _LegendItem(color: AppColors.orange, label: '30–40°'),
              _LegendItem(color: AppColors.danger, label: '40°+'),
            ],
          ),
        ],
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(fontSize: 11.5, color: AppColors.textTertiary),
        ),
      ],
    );
  }
}

class _HighlightChip extends StatelessWidget {
  const _HighlightChip({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.textTertiary),
          const SizedBox(width: 6),
          Text(
            '$label ',
            style: const TextStyle(fontSize: 11.5, color: AppColors.textTertiary),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
              fontFeatures: tabularFigures,
            ),
          ),
        ],
      ),
    );
  }
}

class _LeanBands extends StatelessWidget {
  const _LeanBands({required this.bands});

  final List<LeanBandStat> bands;

  @override
  Widget build(BuildContext context) {
    final maxFraction = bands.fold<double>(
      1.0,
      (value, band) => math.max(value, band.fraction),
    );
    return Column(
      children: [
        for (final band in bands)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                SizedBox(
                  width: 60,
                  child: Text(
                    band.label,
                    maxLines: 1,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      height: 8,
                      color: AppColors.surfaceHighest,
                      alignment: Alignment.centerLeft,
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(
                          end: maxFraction == 0
                              ? 0.0
                              : band.fraction / maxFraction,
                        ),
                        duration: AppMotion.reduced(context)
                            ? Duration.zero
                            : const Duration(milliseconds: 700),
                        curve: AppMotion.curve,
                        builder: (context, factor, _) => FractionallySizedBox(
                          widthFactor: factor.clamp(0.0, 1.0),
                          child: Container(
                            color: band.lowerDeg == 0
                                ? AppColors.textTertiary
                                : leanColor(
                                    (band.lowerDeg + band.upperDeg) / 2,
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 86,
                  child: Text(
                    '${(band.fraction * 100).round()}% · ${formatDuration(band.seconds)}',
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.fade,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textTertiary,
                      fontFeatures: tabularFigures,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _SpeedChart extends StatefulWidget {
  const _SpeedChart({required this.points, required this.unit});

  final List<SpeedPoint> points;
  final SpeedUnit unit;

  @override
  State<_SpeedChart> createState() => _SpeedChartState();
}

class _SpeedChartState extends State<_SpeedChart>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final points = widget.points;
    if (points.length < 2) {
      return const SizedBox(
        height: 120,
        child: Center(
          child: Text(
            '没有足够的速度数据',
            style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
          ),
        ),
      );
    }
    final unit = widget.unit;
    double toUnit(double kmh) => unit.fromMps(kmh / 3.6);
    final maxSpeed = points.fold<double>(
      0.0,
      (value, point) => math.max(value, toUnit(point.speedKmh)),
    );
    final maxY = math.max(20.0, (maxSpeed / 20).ceil() * 20.0);
    final duration = math.max(1.0, points.last.tSeconds);
    final intervalY = (maxY / 4).clamp(5, 100).toDouble();
    final intervalX = math.max(1.0, duration / 3);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        // 曲线从左到右「画」出来：按进度截断数据点，坐标轴保持稳定。
        final progress = AppMotion.reduced(context)
            ? 1.0
            : AppMotion.curve.transform(_controller.value);
        final count = (1 + progress * (points.length - 1)).ceil().clamp(
          2,
          points.length,
        );
        final visible = points.sublist(0, count);

        return SizedBox(
          height: 176,
          child: LineChart(
            duration: Duration.zero,
            LineChartData(
              minX: 0,
              maxX: duration,
              minY: 0,
              maxY: maxY,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: intervalY,
                getDrawingHorizontalLine: (value) =>
                    const FlLine(color: AppColors.divider, strokeWidth: 1),
              ),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 32,
                    interval: intervalY,
                    getTitlesWidget: (value, meta) => Text(
                      value.round().toString(),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 24,
                    interval: intervalX,
                    getTitlesWidget: (value, meta) => Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        formatDuration(value.round()),
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              borderData: FlBorderData(show: false),
              lineTouchData: const LineTouchData(enabled: false),
              lineBarsData: [
                LineChartBarData(
                  spots: [
                    for (final point in visible)
                      FlSpot(point.tSeconds, toUnit(point.speedKmh)),
                  ],
                  isCurved: true,
                  curveSmoothness: 0.22,
                  barWidth: 2.5,
                  color: AppColors.accent,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(
                    show: true,
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        AppColors.accent.withValues(alpha: 0.18),
                        AppColors.accent.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: AppColors.danger,
              size: 36,
            ),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                height: 1.6,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 18),
            OutlinedButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}
