import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../services/location_service.dart';
import '../services/ride_recorder.dart';
import '../services/ride_store.dart';
import '../services/sensor_service.dart';
import '../services/settings_service.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../utils/units.dart';
import '../widgets/lean_gauge.dart';
import '../widgets/motion.dart';
import '../widgets/ride_map.dart';
import '../widgets/stat_tile.dart';

class RecordScreen extends StatefulWidget {
  const RecordScreen({super.key, required this.store, required this.settings});

  final RideStore store;
  final SettingsService settings;

  @override
  State<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends State<RecordScreen> {
  late final RideRecorder _recorder;
  bool _screenAwake = false;
  bool _nightMode = false;
  bool _handlingBack = false;
  bool _stopping = false;
  RecorderState? _prevState;
  double _lastMaxLean = 0;
  DateTime _lastLeanHaptic = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _nightMode = widget.settings.nightDashboard;
    _recorder = RideRecorder(
      store: widget.store,
      locationService: LocationService(),
      sensorService: SensorService(),
      calibrationSeconds: widget.settings.calibrationSeconds,
    );
    _recorder.addListener(_onRecorderChanged);
    if (widget.settings.defaultScreenAwake) {
      _screenAwake = true;
      unawaited(WakelockPlus.enable().catchError((_) {}));
    }
  }

  @override
  void dispose() {
    _recorder.removeListener(_onRecorderChanged);
    _recorder.dispose();
    if (_screenAwake) {
      unawaited(WakelockPlus.disable());
    }
    super.dispose();
  }

  /// 状态与极值变化的触觉反馈：校准完成、刷新本趟最大倾角。
  void _onRecorderChanged() {
    if (!mounted) {
      return;
    }
    final prev = _prevState;
    final state = _recorder.state;
    if (prev != state) {
      if (prev == RecorderState.calibrating &&
          state == RecorderState.recording) {
        HapticFeedback.mediumImpact();
      }
      _prevState = state;
    }
    if (state == RecorderState.recording) {
      final maxLean = math.max(
        _recorder.maxLeanLeftDeg,
        _recorder.maxLeanRightDeg,
      );
      if (maxLean > _lastMaxLean + 0.5) {
        _lastMaxLean = maxLean;
        if (DateTime.now().difference(_lastLeanHaptic) >
            const Duration(milliseconds: 2500)) {
          _lastLeanHaptic = DateTime.now();
          HapticFeedback.lightImpact();
        }
      }
    }
  }

  Future<void> _toggleScreenAwake() async {
    try {
      if (_screenAwake) {
        await WakelockPlus.disable();
      } else {
        await WakelockPlus.enable();
      }
      if (mounted) {
        setState(() => _screenAwake = !_screenAwake);
      }
    } catch (_) {
      _showSnack('无法切换屏幕常亮');
    }
  }

  /// 骑行中随时切换深色仪表盘；写入设置作为下次进入的默认值。
  void _toggleNightMode() {
    HapticFeedback.selectionClick();
    setState(() => _nightMode = !_nightMode);
    unawaited(widget.settings.setNightDashboard(_nightMode));
  }

  Future<void> _handleBack() async {
    if (_handlingBack) {
      return;
    }
    _handlingBack = true;
    try {
      final state = _recorder.state;
      if (state == RecorderState.recording || state == RecorderState.paused) {
        final shouldStop = widget.settings.confirmBeforeStop
            ? await _askStop()
            : true;
        if (shouldStop == true) {
          await _stopAndPop();
        }
      } else if (state == RecorderState.saving) {
        return;
      } else {
        await _recorder.cancel();
        if (mounted) {
          Navigator.of(context).pop();
        }
      }
    } finally {
      _handlingBack = false;
    }
  }

  Future<bool?> _askStop() {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('结束本次骑行？'),
        content: const Text('当前数据会保存到本机，结束后可以查看轨迹、倾角与速度统计。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('继续骑行'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 44),
              padding: const EdgeInsets.symmetric(horizontal: 18),
            ),
            child: const Text('结束并保存'),
          ),
        ],
      ),
    );
  }

  Future<void> _stopAndPop() async {
    if (_stopping) {
      return;
    }
    _stopping = true;
    try {
      final sessionId = await _recorder.stop();
      if (_screenAwake) {
        await WakelockPlus.disable();
        _screenAwake = false;
      }
      if (!mounted) {
        return;
      }
      if (sessionId == null) {
        _showSnack(_recorder.errorMessage ?? '保存失败，请重试');
        return;
      }
      HapticFeedback.mediumImpact();
      Navigator.of(context).pop(sessionId);
    } finally {
      _stopping = false;
    }
  }

  void _showSnack(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _handleBack();
        }
      },
      child: Scaffold(
        body: SafeArea(
          child: AnimatedBuilder(
            animation: _recorder,
            builder: (context, _) {
              final stateWidget = switch (_recorder.state) {
                RecorderState.idle => _buildIntro(),
                RecorderState.preparing => _buildPreparing(),
                RecorderState.calibrating => _buildCalibrating(),
                RecorderState.failed => _buildFailure(),
                RecorderState.recording ||
                RecorderState.paused => _buildDashboard(),
                RecorderState.saving ||
                RecorderState.finished => _buildSaving(),
              };
              // 记录中/暂停共用同一棵子树，切换暂停时不重播入场动画。
              final switchKey = switch (_recorder.state) {
                RecorderState.recording || RecorderState.paused => 'dash',
                RecorderState.saving || RecorderState.finished => 'saving',
                RecorderState.idle => 'idle',
                RecorderState.preparing => 'preparing',
                RecorderState.calibrating => 'calibrating',
                RecorderState.failed => 'failed',
              };
              final reduced = AppMotion.reduced(context);
              return AnimatedSwitcher(
                duration: reduced ? AppMotion.fast : AppMotion.med,
                switchInCurve: AppMotion.curve,
                switchOutCurve: AppMotion.curveExit,
                // 子树内含 Expanded，Stack 需要给满约束。
                layoutBuilder: (currentChild, previousChildren) => Stack(
                  fit: StackFit.expand,
                  alignment: Alignment.topCenter,
                  children: [...previousChildren, ?currentChild],
                ),
                transitionBuilder: (child, animation) {
                  final faded = FadeTransition(
                    opacity: animation,
                    child: child,
                  );
                  if (reduced) {
                    return faded;
                  }
                  return ScaleTransition(
                    scale: Tween<double>(
                      begin: 0.985,
                      end: 1,
                    ).animate(animation),
                    child: faded,
                  );
                },
                child: KeyedSubtree(
                  key: ValueKey(switchKey),
                  child: stateWidget,
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildIntro() {
    return Column(
      children: [
        _TopBar(onClose: _handleBack, title: '准备记录'),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: AppColors.accentSoft,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: AppColors.accent.withValues(alpha: 0.25),
                    ),
                  ),
                  child: const Icon(
                    Icons.terrain_rounded,
                    color: AppColors.accentInk,
                    size: 32,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  '出发前，\n先固定好手机。',
                  style: TextStyle(
                    fontSize: 32,
                    height: 1.12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1,
                  ),
                ),
                const SizedBox(height: 24),
                const _StepCard(
                  number: '01',
                  title: '固定方向',
                  body: '手机 X 轴指向车身右侧。竖装屏幕朝骑手，平放顶部朝车头。',
                  icon: Icons.phone_android_rounded,
                ),
                const SizedBox(height: 10),
                _StepCard(
                  number: '02',
                  title: '扶正车身',
                  body:
                      '开始后保持静止 '
                      '${_recorder.calibrationSeconds} 秒，完成零位校准。',
                  icon: Icons.straighten_rounded,
                ),
                const SizedBox(height: 10),
                const _StepCard(
                  number: '03',
                  title: '允许后台定位',
                  body: '熄屏记录需要「始终允许」定位权限。',
                  icon: Icons.my_location_rounded,
                ),
                const SizedBox(height: 24),
                PressableScale(
                  child: FilledButton.icon(
                    onPressed: _recorder.start,
                    icon: const Icon(Icons.sensors_rounded, size: 22),
                    label: const Text('开始校准并记录'),
                  ),
                ),
                const SizedBox(height: 10),
                Center(
                  child: Text(
                    '骑行中请勿操作手机，安全回家最重要。',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textTertiary.withValues(alpha: 0.8),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPreparing() {
    return Column(
      children: [
        _TopBar(onClose: _handleBack, title: '准备中'),
        const Expanded(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 32,
                  height: 32,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
                SizedBox(height: 18),
                Text(
                  '正在检查定位与通知权限…',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCalibrating() {
    final progress = _recorder.calibrationProgress;
    final total = _recorder.calibrationSeconds;
    final remaining = (total * (1 - progress)).ceil().clamp(1, total);
    return Column(
      children: [
        _TopBar(onClose: _handleBack, title: '校准'),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
            child: Column(
              children: [
                const SizedBox(height: 8),
                SizedBox(
                  width: 196,
                  height: 196,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 196,
                        height: 196,
                        child: CircularProgressIndicator(
                          value: progress,
                          strokeWidth: 5,
                          backgroundColor: AppColors.surfaceHigh,
                          strokeCap: StrokeCap.round,
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '$remaining',
                            style: displayNumber(
                              fontSize: 78,
                              color: AppColors.accent,
                              letterSpacing: -2,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            '秒',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  '扶正车身，保持静止',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  '正在校准倾角零位，请不要触碰手机。',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 20),
                _LevelBubble(leanDeg: _recorder.leanDeg),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: cardDecoration(),
                  child: const Column(
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.screen_rotation_rounded,
                            size: 18,
                            color: AppColors.accentInk,
                          ),
                          SizedBox(width: 10),
                          Text(
                            '手机方向检查',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 10),
                      Text(
                        '竖装：屏幕朝向骑手、顶部朝上\n平放：屏幕朝上、顶部朝车头\n两种情况手机的右侧都要指向车身右侧',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.8,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                TextButton(
                  onPressed: _handleBack,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                  ),
                  child: const Text('取消'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFailure() {
    final error = _recorder.errorMessage ?? '未知错误';
    return Column(
      children: [
        _TopBar(onClose: _handleBack, title: '无法开始'),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
            child: Column(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: AppColors.danger.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.error_outline_rounded,
                    color: AppColors.danger,
                    size: 30,
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  '记录没有启动',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                Text(
                  error,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.6,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  '如果使用的是模拟器或没有传感器的设备，加速度计可能不可用。可以先返回首页载入演示行程，查看完整的记录与统计效果。',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.6,
                    color: AppColors.textTertiary,
                  ),
                ),
                const SizedBox(height: 26),
                FilledButton.icon(
                  onPressed: _recorder.start,
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                  label: const Text('重试'),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () => _recorder.locationService.openSettings(),
                  icon: const Icon(Icons.settings_outlined, size: 18),
                  label: const Text('打开系统设置'),
                ),
                const SizedBox(height: 6),
                TextButton(onPressed: _handleBack, child: const Text('返回首页')),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDashboard() {
    final paused = _recorder.state == RecorderState.paused;
    final recording = _recorder.state == RecorderState.recording;
    final unit = widget.settings.speedUnit;
    final distanceUnit = widget.settings.distanceUnit;
    final dark = _nightMode;
    // 深色仪表盘的语义色：在碳黑底上亮一档，保证对比度。
    final textPrimary = dark ? AppDash.textPrimary : AppColors.textPrimary;
    final textSecondary = dark
        ? AppDash.textSecondary
        : AppColors.textSecondary;
    final textTertiary = dark ? AppDash.textTertiary : AppColors.textTertiary;
    final dividerColor = dark ? AppDash.divider : AppColors.divider;
    final accentInkLike = dark ? AppDash.accent : AppColors.accentInk;
    final amberLike = dark ? AppDash.amber : AppColors.amber;
    final dangerLike = dark ? AppDash.danger : AppColors.danger;
    final track = [
      for (final point in _recorder.track)
        RideMapPoint(lat: point.lat, lon: point.lon, leanDeg: point.leanDeg),
    ];
    final gpsLabel = !_recorder.gpsFresh
        ? '等待 GPS'
        : 'GPS ±${(_recorder.gpsAccuracyM ?? 0).round()}m';
    final gpsColor = !_recorder.gpsFresh
        ? textTertiary
        : (_recorder.gpsAccuracyM ?? 99) <= 25
        ? accentInkLike
        : (_recorder.gpsAccuracyM ?? 99) <= 45
        ? amberLike
        : dangerLike;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Container(
        color: dark ? AppDash.background : null,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 12, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: _handleBack,
                    tooltip: '结束记录',
                    icon: Icon(Icons.close_rounded, color: textPrimary),
                  ),
                  const SizedBox(width: 2),
                  _LivePill(paused: paused, dark: dark),
                  const SizedBox(width: 14),
                  Text(
                    formatDuration(_recorder.elapsedSeconds),
                    style: displayNumber(
                      fontSize: 26,
                      letterSpacing: -0.3,
                      color: textPrimary,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: _toggleNightMode,
                    tooltip: dark ? '切换浅色仪表盘' : '切换夜间仪表盘',
                    style: IconButton.styleFrom(
                      backgroundColor: dark
                          ? AppDash.accent.withValues(alpha: 0.14)
                          : AppColors.surface,
                      side: BorderSide(
                        color: dark
                            ? AppDash.accent.withValues(alpha: 0.35)
                            : AppColors.divider,
                      ),
                    ),
                    icon: Icon(
                      dark ? Icons.dark_mode_rounded : Icons.dark_mode_outlined,
                      size: 20,
                      color: dark ? AppDash.accent : AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _toggleScreenAwake,
                    tooltip: _screenAwake ? '关闭屏幕常亮' : '开启屏幕常亮',
                    style: IconButton.styleFrom(
                      backgroundColor: _screenAwake
                          ? (dark
                                ? AppDash.accent.withValues(alpha: 0.14)
                                : AppColors.accentSoft)
                          : (dark ? AppDash.surface : AppColors.surface),
                      side: BorderSide(
                        color: _screenAwake
                            ? (dark ? AppDash.accent : AppColors.accent)
                                  .withValues(alpha: 0.35)
                            : dividerColor,
                      ),
                    ),
                    icon: Icon(
                      Icons.light_mode_rounded,
                      size: 20,
                      color: _screenAwake
                          ? accentInkLike
                          : (dark
                                ? AppDash.textSecondary
                                : AppColors.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Column(
                  children: [
                    if (_recorder.calibrationWarning != null)
                      _InlineBanner(
                        icon: Icons.straighten_rounded,
                        color: amberLike,
                        dark: dark,
                        text: '校准提示：${_recorder.calibrationWarning}',
                      ),
                    if (!_recorder.backgroundAllowed)
                      _InlineBanner(
                        icon: Icons.nightlight_round,
                        color: amberLike,
                        dark: dark,
                        text: '未开启“始终允许”定位，熄屏后可能中断记录。',
                        actionLabel: '去设置',
                        onAction: () =>
                            _recorder.locationService.openSettings(),
                      ),
                    if (paused)
                      _InlineBanner(
                        icon: Icons.pause_circle_outline_rounded,
                        color: dark ? AppDash.blue : AppColors.blue,
                        dark: dark,
                        text: '已暂停，速度、倾角与轨迹不会写入本次行程。',
                      ),
                    AnimatedSlide(
                      offset: paused ? const Offset(0, -0.015) : Offset.zero,
                      duration: AppMotion.fast,
                      curve: AppMotion.curve,
                      child: AnimatedOpacity(
                        opacity: paused ? 0.42 : 1,
                        duration: const Duration(milliseconds: 220),
                        child: Column(
                          children: [
                            const SizedBox(height: 10),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                TweenAnimationBuilder<double>(
                                  tween: Tween(end: _recorder.speedKmh),
                                  duration: AppMotion.reduced(context)
                                      ? Duration.zero
                                      : const Duration(milliseconds: 350),
                                  curve: AppMotion.curve,
                                  builder: (context, speedKmh, _) => Text(
                                    formatSpeedValue(speedKmh / 3.6, unit),
                                    style: displayNumber(
                                      fontSize: 96,
                                      letterSpacing: -2,
                                      height: 0.86,
                                      color: textPrimary,
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(
                                    bottom: 10,
                                    left: 6,
                                  ),
                                  child: Text(
                                    unit.label,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: textSecondary.withValues(
                                        alpha: 0.9,
                                      ),
                                    ),
                                  ),
                                ),
                                const Spacer(),
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        '本次最高',
                                        style: TextStyle(
                                          fontSize: 12,
                                          letterSpacing: 0.8,
                                          color: textTertiary,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        formatSpeedWithUnit(
                                          _recorder.maxSpeedKmh / 3.6,
                                          unit,
                                        ),
                                        style: displayNumber(
                                          fontSize: 15,
                                          slanted: false,
                                          color: textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            LeanGauge(
                              leanDeg: _recorder.leanDeg,
                              maxLeftDeg: _recorder.maxLeanLeftDeg,
                              maxRightDeg: _recorder.maxLeanRightDeg,
                              dark: dark,
                            ),
                          ],
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: StatTile(
                            label: '距离',
                            value: formatDistanceWithUnit(
                              _recorder.distanceM,
                              distanceUnit,
                            ),
                            height: 80,
                            dark: dark,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: StatTile(
                            label: '移动',
                            value: formatDuration(_recorder.movingSeconds),
                            height: 80,
                            dark: dark,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: StatTile(
                            label: '均速',
                            value: formatSpeedValue(
                              _recorder.avgSpeedKmh / 3.6,
                              unit,
                            ),
                            unit: unit.label,
                            height: 80,
                            accent: true,
                            dark: dark,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Text(
                          '实时轨迹',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: textSecondary,
                          ),
                        ),
                        const Spacer(),
                        _StatusChip(label: gpsLabel, color: gpsColor),
                        const SizedBox(width: 6),
                        _StatusChip(
                          label: _recorder.sensorFresh ? 'IMU 正常' : 'IMU 无数据',
                          color: _recorder.sensorFresh
                              ? accentInkLike
                              : dangerLike,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (widget.settings.showLiveTrack)
                      RideMap(
                        points: track,
                        live: true,
                        height: 158,
                        // 夜间仪表盘强制暗色底图，避免一块亮图破坏整体。
                        mapStyle: dark
                            ? MapStyle.dark
                            : widget.settings.mapStyle,
                      ),
                    if (_recorder.gpsError != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _recorder.gpsError!,
                        style: TextStyle(fontSize: 11.5, color: amberLike),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
              decoration: BoxDecoration(
                color: dark ? AppDash.background : AppColors.background,
                border: Border(top: BorderSide(color: dividerColor)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: PressableScale(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          HapticFeedback.selectionClick();
                          if (paused) {
                            _recorder.resume();
                          } else if (recording) {
                            _recorder.pause();
                          }
                        },
                        icon: Icon(
                          paused
                              ? Icons.play_arrow_rounded
                              : Icons.pause_rounded,
                          size: 20,
                        ),
                        label: Text(paused ? '继续记录' : '暂停'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(54),
                          foregroundColor: paused ? accentInkLike : textPrimary,
                          side: BorderSide(
                            color: paused
                                ? accentInkLike.withValues(alpha: 0.4)
                                : dividerColor,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: PressableScale(
                      child: FilledButton.icon(
                        onPressed: _askStopAndStop,
                        style: FilledButton.styleFrom(
                          backgroundColor: dangerLike,
                          foregroundColor: dark
                              ? AppDash.onDanger
                              : Colors.white,
                          minimumSize: const Size.fromHeight(54),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        icon: const Icon(Icons.stop_rounded, size: 22),
                        label: const Text('结束'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _askStopAndStop() async {
    final shouldStop = await _askStop();
    if (shouldStop == true) {
      await _stopAndPop();
    }
  }

  Widget _buildSaving() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
          SizedBox(height: 18),
          Text(
            '正在保存本次骑行…',
            style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
          ),
          SizedBox(height: 6),
          Text(
            '写入本地数据库',
            style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onClose, required this.title});

  final VoidCallback onClose;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 16, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: onClose,
            tooltip: '返回',
            icon: const Icon(Icons.close_rounded),
          ),
          const SizedBox(width: 2),
          Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.number,
    required this.title,
    required this.body,
    required this.icon,
  });

  final String number;
  final String title;
  final String body;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: cardDecoration(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.surfaceHigh,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 20, color: AppColors.accentInk),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      number,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                        color: AppColors.accentInk,
                        fontFeatures: tabularFigures,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  body,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.65,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LivePill extends StatelessWidget {
  const _LivePill({required this.paused, this.dark = false});

  final bool paused;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final color = paused
        ? (dark ? AppDash.amber : AppColors.amber)
        : (dark ? AppDash.danger : AppColors.danger);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PulsingDot(color: color, animate: !paused),
          const SizedBox(width: 6),
          Text(
            paused ? '已暂停' : '记录中',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _PulsingDot extends StatefulWidget {
  const _PulsingDot({required this.color, required this.animate});

  final Color color;
  final bool animate;

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: widget.animate
          ? Tween<double>(begin: 0.35, end: 1).animate(
              CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
            )
          : const AlwaysStoppedAnimation<double>(1),
      child: Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
      ),
    );
  }
}

class _InlineBanner extends StatelessWidget {
  const _InlineBanner({
    required this.icon,
    required this.color,
    required this.text,
    this.actionLabel,
    this.onAction,
    this.dark = false,
  });

  final IconData icon;
  final Color color;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                height: 1.45,
                color: dark ? AppDash.textSecondary : AppColors.textSecondary,
              ),
            ),
          ),
          if (actionLabel != null && onAction != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 44),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                foregroundColor: color,
                textStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              child: Text(actionLabel!),
            ),
        ],
      ),
    );
  }
}

/// GPS / IMU 状态小标签。
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// 校准期间的实时水平泡：原始重力倾角驱动游标，|倾角| < 2° 视为扶正。
class _LevelBubble extends StatelessWidget {
  const _LevelBubble({required this.leanDeg});

  final double leanDeg;

  @override
  Widget build(BuildContext context) {
    final upright = leanDeg.abs() < 2;
    final bubbleColor = upright ? AppColors.accentInk : AppColors.textTertiary;
    return Semantics(
      label:
          '当前倾斜 ${leanDeg.abs().toStringAsFixed(1)} 度'
          '${upright ? '，已扶正' : ''}',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: cardDecoration(),
          child: Row(
            children: [
              Icon(Icons.straighten_rounded, size: 18, color: bubbleColor),
              const SizedBox(width: 12),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final half = constraints.maxWidth / 2;
                    // ±15° 映射满幅，超出钳制在轨道两端。
                    final offset =
                        (leanDeg.clamp(-15.0, 15.0) / 15) * (half - 7);
                    return SizedBox(
                      height: 26,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              color: AppColors.surfaceHigh,
                              borderRadius: BorderRadius.circular(13),
                            ),
                          ),
                          Container(
                            width: 26,
                            decoration: BoxDecoration(
                              color: bubbleColor.withValues(
                                alpha: upright ? 0.25 : 0.12,
                              ),
                              borderRadius: BorderRadius.circular(13),
                            ),
                          ),
                          Transform.translate(
                            offset: Offset(offset, 0),
                            child: Container(
                              width: 14,
                              height: 14,
                              decoration: BoxDecoration(
                                color: bubbleColor,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 2,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 56,
                child: Text(
                  '${leanDeg.abs().toStringAsFixed(1)}°',
                  textAlign: TextAlign.right,
                  style: displayNumber(
                    fontSize: 20,
                    slanted: false,
                    color: bubbleColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
