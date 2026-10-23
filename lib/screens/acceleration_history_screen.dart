import 'package:flutter/material.dart';

import '../models/acceleration_run.dart';
import '../services/ride_store.dart';
import '../services/settings_service.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../utils/units.dart';
import 'acceleration_result_screen.dart';
import 'acceleration_screen.dart';

class AccelerationHistoryScreen extends StatefulWidget {
  const AccelerationHistoryScreen({
    super.key,
    required this.store,
    required this.settings,
  });

  final RideStore store;
  final SettingsService settings;

  @override
  State<AccelerationHistoryScreen> createState() =>
      _AccelerationHistoryScreenState();
}

class _AccelerationHistoryScreenState extends State<AccelerationHistoryScreen> {
  List<AccelerationRun> _runs = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final runs = await widget.store.loadAccelerationRuns();
      if (!mounted) {
        return;
      }
      setState(() {
        _runs = runs;
        _loading = false;
        _error = null;
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

  Future<void> _openResult(AccelerationRun run) async {
    final id = run.id;
    if (id == null) {
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => AccelerationResultScreen(
          store: widget.store,
          settings: widget.settings,
          runId: id,
        ),
      ),
    );
    if (mounted) {
      await _load();
    }
  }

  Future<void> _startNew() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => AccelerationScreen(
          store: widget.store,
          settings: widget.settings,
        ),
      ),
    );
    if (mounted) {
      await _load();
    }
  }

  Future<bool> _confirmDelete(AccelerationRun run) async {
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
    if (confirmed != true) {
      return false;
    }
    final id = run.id;
    if (id != null) {
      try {
        await widget.store.deleteAccelerationRun(id);
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('删除失败：$error')),
          );
        }
        return false;
      }
    }
    if (mounted) {
      setState(() => _runs.remove(run));
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('加速成绩'),
        actions: [
          IconButton(
            onPressed: _startNew,
            tooltip: '开始测试',
            icon: const Icon(Icons.add_rounded),
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
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                )
              : _runs.isEmpty
                  ? _EmptyState(onStart: _startNew)
                  : _buildList(),
    );
  }

  Widget _buildList() {
    final validRuns = _runs.where((run) => run.valid).toList();
    final best = validRuns.isEmpty
        ? null
        : validRuns.reduce(
            (a, b) => a.resultMs <= b.resultMs ? a : b,
          );
    final best60 = validRuns
        .where((run) => run.result60Ms != null)
        .fold<AccelerationRun?>(null, (best, run) {
      if (best == null) {
        return run;
      }
      return run.result60Ms! < best.result60Ms! ? run : best;
    });
    final distanceUnit = widget.settings.distanceUnit;

    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.accent,
      backgroundColor: AppColors.surfaceHigh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        children: [
          Row(
            children: [
              Expanded(
                child: _SummaryCard(
                  label: '测试次数',
                  value: '${_runs.length}',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _SummaryCard(
                  label: '最佳 0–100',
                  value: best == null
                      ? '—'
                      : '${best.resultSeconds.toStringAsFixed(2)} s',
                  accent: true,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _SummaryCard(
                  label: '最佳 0–60',
                  value: best60 == null
                      ? '—'
                      : '${(best60.result60Ms! / 1000).toStringAsFixed(2)} s',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            '全部成绩',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          for (final run in _runs) ...[
            Dismissible(
              key: ValueKey('accel_run_${run.id ?? run.startedAt.millisecondsSinceEpoch}'),
              direction: DismissDirection.endToStart,
              confirmDismiss: (_) => _confirmDelete(run),
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 20),
                decoration: BoxDecoration(
                  color: AppColors.danger.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(
                  Icons.delete_rounded,
                  color: AppColors.danger,
                ),
              ),
              child: _RunCard(
                run: run,
                distanceUnit: distanceUnit,
                onTap: () => _openResult(run),
              ),
            ),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 12),
          const Text(
            '成绩为手机 GPS 估算值，适合同一设备横向对比。',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 10,
              height: 1.6,
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

class _RunCard extends StatelessWidget {
  const _RunCard({
    required this.run,
    required this.distanceUnit,
    required this.onTap,
  });

  final AccelerationRun run;
  final DistanceUnit distanceUnit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final active = run.valid;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: cardDecoration(),
          child: Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        run.resultSeconds.toStringAsFixed(2),
                        style: TextStyle(
                          fontSize: 30,
                          height: 1,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1.5,
                          color: active
                              ? AppColors.accent
                              : AppColors.textTertiary,
                          fontFeatures: tabularFigures,
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.only(bottom: 2, left: 2),
                        child: Text(
                          's',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '0–${run.targetSpeedKmh.round()} km/h',
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            formatDateWithWeekday(run.startedAt),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (run.isDemo) ...[
                          const SizedBox(width: 6),
                          const _Badge(label: '演示', color: AppColors.accent),
                        ],
                        if (!run.valid) ...[
                          const SizedBox(width: 6),
                          const _Badge(
                            label: '数据不足',
                            color: AppColors.amber,
                          ),
                        ],
                        if (run.rollout) ...[
                          const SizedBox(width: 6),
                          const _Badge(
                            label: 'rollout',
                            color: AppColors.textTertiary,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      [
                        formatClock(run.startedAt),
                        if (run.result60Seconds != null)
                          '0–60 ${run.result60Seconds!.toStringAsFixed(2)}s',
                        if (run.distanceM != null)
                          formatDistanceWithUnit(run.distanceM!, distanceUnit),
                        if (run.gradePercent != null)
                          '坡度 ${run.gradePercent!.toStringAsFixed(1)}%',
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: AppColors.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 8,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
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
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: cardDecoration(),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              fontFeatures: tabularFigures,
              color: accent ? AppColors.accent : AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: const TextStyle(
              fontSize: 9.5,
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: AppColors.surfaceHigh,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.speed_rounded,
                color: AppColors.accent,
                size: 30,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '还没有加速成绩',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            const Text(
              '找一段封闭直道，停车、保持静止，然后开始第一次测试。',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: AppColors.textTertiary,
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onStart,
              icon: const Icon(Icons.play_arrow_rounded, size: 20),
              label: const Text('去测一次'),
            ),
          ],
        ),
      ),
    );
  }
}
