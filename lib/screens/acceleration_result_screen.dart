import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../models/acceleration_run.dart';
import '../models/acceleration_sample.dart';
import '../services/ride_store.dart';
import '../services/settings_service.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../utils/units.dart';
import '../widgets/ride_map.dart';

class AccelerationResultScreen extends StatefulWidget {
  const AccelerationResultScreen({
    super.key,
    required this.store,
    required this.settings,
    required this.runId,
  });

  final RideStore store;
  final SettingsService settings;
  final int runId;

  @override
  State<AccelerationResultScreen> createState() =>
      _AccelerationResultScreenState();
}

class _AccelerationResultScreenState extends State<AccelerationResultScreen> {
  AccelerationRun? _run;
  List<AccelerationSample> _samples = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final run = await widget.store.loadAccelerationRun(widget.runId);
      final samples = run == null
          ? <AccelerationSample>[]
          : await widget.store.loadAccelerationSamples(widget.runId);
      if (!mounted) {
        return;
      }
      setState(() {
        _run = run;
        _samples = samples;
        _loading = false;
        _error = run == null ? '找不到这条成绩，可能已经被删除。' : null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = '读取成绩失败：$error';
      });
    }
  }

  Future<void> _share(AccelerationRun run) async {
    final unit = widget.settings.speedUnit;
    final lines = [
      '摩倾 · 零百加速成绩',
      '${run.rollout ? '含 1 英尺 rollout · ' : ''}${formatDateWithWeekday(run.startedAt)}',
      '0–${run.targetSpeedKmh.round()} km/h：${run.resultSeconds.toStringAsFixed(2)} 秒',
      if (run.result60Seconds != null)
        '0–60：${run.result60Seconds!.toStringAsFixed(2)} 秒',
      if (run.result130Seconds != null)
        '60–130：${run.result130Seconds!.toStringAsFixed(2)} 秒',
      if (run.distanceM != null)
        '起步距离：${formatDistanceWithUnit(run.distanceM!, widget.settings.distanceUnit)}',
      if (run.gradePercent != null)
        '坡度：${run.gradePercent!.toStringAsFixed(1)}%',
      if (run.gpsAccuracyM != null) 'GPS 精度：±${run.gpsAccuracyM!.round()} m',
      unit == SpeedUnit.kmh ? '' : '',
      '手机 GPS 估算，仅供参考',
    ].where((line) => line.isNotEmpty).toList();

    try {
      await SharePlus.instance.share(
        ShareParams(text: lines.join('\n'), subject: '摩倾零百成绩'),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('分享失败：$error')));
      }
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这条成绩？'),
        content: const Text('成绩与采样数据将被永久删除，无法恢复。'),
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
      await widget.store.deleteAccelerationRun(widget.runId);
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
    final run = _run;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('加速成绩'),
        actions: [
          if (run != null)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_horiz_rounded),
              color: AppColors.surfaceHigh,
              onSelected: (value) {
                switch (value) {
                  case 'share':
                    _share(run);
                    break;
                  case 'delete':
                    _delete();
                    break;
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'share', child: Text('分享成绩')),
                PopupMenuItem(
                  value: 'delete',
                  child: Text(
                    '删除成绩',
                    style: TextStyle(color: AppColors.danger),
                  ),
                ),
              ],
            ),
          const SizedBox(width: 6),
        ],
      ),
      body: _loading
          ? const Center(
              child: SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : _error != null || run == null
          ? _ErrorView(message: _error ?? '未知错误', onRetry: _load)
          : _buildContent(run),
    );
  }

  Widget _buildContent(AccelerationRun run) {
    final unit = widget.settings.speedUnit;
    final distanceUnit = widget.settings.distanceUnit;
    final points = [
      for (final sample in _samples)
        if (sample.hasPosition)
          RideMapPoint(lat: sample.lat!, lon: sample.lon!, leanDeg: 0),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    formatDateWithWeekday(run.startedAt),
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textTertiary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    formatClock(run.startedAt),
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            if (run.isDemo)
              _Tag(label: '演示', color: AppColors.accent)
            else if (!run.valid)
              _Tag(label: '数据不足', color: AppColors.amber),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(24, 26, 24, 22),
          decoration: cardDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF202B0E), Color(0xFF121418)],
            ),
          ),
          child: Column(
            children: [
              Text(
                '0–${run.targetSpeedKmh.round()} km/h',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 6),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.85, end: 1),
                duration: AppMotion.reduced(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 550),
                curve: Curves.easeOutBack,
                builder: (context, scale, child) =>
                    Transform.scale(scale: scale, child: child),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      run.resultSeconds.toStringAsFixed(2),
                      style: TextStyle(
                        fontSize: 84,
                        height: 0.95,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -4,
                        color: run.valid
                            ? AppColors.accent
                            : AppColors.textTertiary,
                        fontFeatures: tabularFigures,
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.only(bottom: 10, left: 4),
                      child: Text(
                        '秒',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (run.rollout) ...[
                const SizedBox(height: 4),
                const Text(
                  '含 1 英尺 rollout',
                  style: TextStyle(
                    fontSize: 10,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (!run.valid && run.invalidReason != null) ...[
          const SizedBox(height: 12),
          _InlineNote(
            icon: Icons.info_outline_rounded,
            text: run.invalidReason!,
          ),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _StatCard(
                label: '0–60',
                value: run.result60Seconds == null
                    ? '—'
                    : '${run.result60Seconds!.toStringAsFixed(2)} s',
                accent: true,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _StatCard(
                label: '60–130',
                value: run.result130Seconds == null
                    ? '—'
                    : '${run.result130Seconds!.toStringAsFixed(2)} s',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _StatCard(
                label: '0–200',
                value: run.result200Seconds == null
                    ? '—'
                    : '${run.result200Seconds!.toStringAsFixed(2)} s',
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _StatCard(
                label: '起步距离',
                value: run.distanceM == null
                    ? '—'
                    : formatDistanceWithUnit(run.distanceM!, distanceUnit),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _StatCard(
                label: '坡度',
                value: run.gradePercent == null
                    ? '—'
                    : '${run.gradePercent!.toStringAsFixed(1)}%',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _StatCard(
                label: 'GPS 精度',
                value: run.gpsAccuracyM == null
                    ? '—'
                    : '±${run.gpsAccuracyM!.round()} m',
              ),
            ),
          ],
        ),
        if (points.isNotEmpty) ...[
          const SizedBox(height: 18),
          const Text(
            '测试轨迹',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          RideMap(
            points: points,
            height: 170,
            mapStyle: widget.settings.mapStyle,
          ),
        ],
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: () => _share(run),
          icon: const Icon(Icons.ios_share_rounded, size: 20),
          label: const Text('分享成绩'),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _delete,
          icon: const Icon(Icons.delete_outline_rounded, size: 20),
          label: const Text('删除这条成绩'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.danger,
            side: BorderSide(color: AppColors.danger.withValues(alpha: 0.35)),
          ),
        ),
        const SizedBox(height: 18),
        const Text(
          '成绩为手机 GPS 估算值（约 ±0.1–0.3 秒），受卫星信号与更新率影响，'
          '适合同一设备横向对比，不适合与专业遥测设备比较绝对值。',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 10,
            height: 1.6,
            color: AppColors.textTertiary,
          ),
        ),
        const SizedBox(height: 6),
        Center(
          child: Text(
            '目标单位：km/h · 显示单位：${unit.label}',
            style: const TextStyle(fontSize: 9, color: AppColors.textTertiary),
          ),
        ),
      ],
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    this.accent = false,
  });

  final String label;
  final String value;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: cardDecoration(),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              fontFeatures: tabularFigures,
              color: accent ? AppColors.accent : AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: const TextStyle(fontSize: 10, color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }
}

class _InlineNote extends StatelessWidget {
  const _InlineNote({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.amber.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.amber.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.amber),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 11,
                height: 1.5,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
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
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}
