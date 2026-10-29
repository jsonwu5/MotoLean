import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../services/acceleration_recorder.dart';
import '../services/location_service.dart';
import '../services/ride_store.dart';
import '../services/settings_service.dart';
import '../theme.dart';
import '../utils/units.dart';
import '../widgets/motion.dart';
import 'acceleration_result_screen.dart';

class AccelerationScreen extends StatefulWidget {
  const AccelerationScreen({
    super.key,
    required this.store,
    required this.settings,
  });

  final RideStore store;
  final SettingsService settings;

  @override
  State<AccelerationScreen> createState() => _AccelerationScreenState();
}

class _AccelerationScreenState extends State<AccelerationScreen> {
  late final AccelerationRecorder _recorder;
  bool _screenAwake = false;
  bool _handlingBack = false;
  int? _lastCountdown;
  AccelerationState? _prevState;

  @override
  void initState() {
    super.initState();
    _recorder = AccelerationRecorder(
      store: widget.store,
      settings: widget.settings,
      locationService: LocationService(),
    );
    _recorder.addListener(_onRecorderChanged);
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

  void _onRecorderChanged() {
    if (!mounted) {
      return;
    }
    final state = _recorder.state;
    // 倒计时逐秒轻触；冲线进入结果时重触反馈。
    if (state == AccelerationState.countdown) {
      final remaining = _recorder.countdownRemaining;
      if (_lastCountdown != remaining) {
        _lastCountdown = remaining;
        HapticFeedback.selectionClick();
      }
    } else {
      _lastCountdown = null;
    }
    if (_prevState != state) {
      if (state == AccelerationState.finished) {
        HapticFeedback.heavyImpact();
      }
      _prevState = state;
    }
    final running =
        _recorder.state == AccelerationState.running ||
        _recorder.state == AccelerationState.countdown;
    if (running && !_screenAwake) {
      _screenAwake = true;
      unawaited(WakelockPlus.enable().catchError((_) {}));
    } else if (!running && _screenAwake) {
      _screenAwake = false;
      unawaited(WakelockPlus.disable().catchError((_) {}));
    }
  }

  Future<void> _handleBack() async {
    if (_handlingBack) {
      return;
    }
    _handlingBack = true;
    try {
      final state = _recorder.state;
      if (state == AccelerationState.running) {
        final stop = await _askStop();
        if (stop == true) {
          await _recorder.finish();
        }
        return;
      }
      if (state == AccelerationState.saving) {
        return;
      }
      await _recorder.cancel();
      if (mounted) {
        Navigator.of(context).pop();
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
        title: const Text('结束本次测试？'),
        content: const Text('已采集的数据会按当前速度计算结果；未达目标速度则不会保存。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('继续测试'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 44),
              padding: const EdgeInsets.symmetric(horizontal: 18),
            ),
            child: const Text('结束'),
          ),
        ],
      ),
    );
  }

  Future<void> _openResult(int runId) async {
    if (!mounted) {
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => AccelerationResultScreen(
          store: widget.store,
          settings: widget.settings,
          runId: runId,
        ),
      ),
    );
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
              switch (_recorder.state) {
                case AccelerationState.idle:
                  return _buildIntro();
                case AccelerationState.waitingGps:
                  return _buildWaitingGps();
                case AccelerationState.ready:
                  return _buildReady();
                case AccelerationState.countdown:
                  return _buildCountdown();
                case AccelerationState.running:
                  return _buildRunning();
                case AccelerationState.saving:
                  return _buildSaving();
                case AccelerationState.finished:
                  return _buildFinished();
                case AccelerationState.failed:
                  return _buildFailed();
              }
            },
          ),
        ),
      ),
    );
  }

  Widget _buildIntro() {
    return Column(
      children: [
        _TopBar(onClose: _handleBack, title: '零百加速'),
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
                    color: AppColors.blueSoft,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: AppColors.blue.withValues(alpha: 0.25),
                    ),
                  ),
                  child: const Icon(
                    Icons.speed_rounded,
                    color: AppColors.blue,
                    size: 32,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  '零到一百，\n几秒？',
                  style: TextStyle(
                    fontSize: 34,
                    height: 1.1,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1,
                  ),
                ),
                const SizedBox(height: 22),
                const _InfoCard(
                  icon: Icons.speed_rounded,
                  title: '成绩口径',
                  body:
                      '默认从静止起算。开启「1 英尺 rollout」后，计时从车辆移动约 30 cm 开始，'
                      '成绩会比静止口径短约 0.2–0.4 秒。',
                ),
                const SizedBox(height: 10),
                const _InfoCard(
                  icon: Icons.health_and_safety_outlined,
                  title: '安全提示',
                  body: '请在封闭场地测试。公共道路上的急加速非常危险，且可能违法。',
                  danger: true,
                ),
                const SizedBox(height: 24),
                PressableScale(
                  child: FilledButton.icon(
                    onPressed: _recorder.prepare,
                    icon: const Icon(Icons.play_arrow_rounded, size: 24),
                    label: const Text('开始检测'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWaitingGps() {
    final accuracy = _recorder.gpsAccuracyM;
    final ready = _recorder.gpsOk;
    return Column(
      children: [
        _TopBar(onClose: _handleBack, title: '等待 GPS'),
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 168,
                    height: 168,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 168,
                          height: 168,
                          child: CircularProgressIndicator(
                            value: accuracy == null
                                ? null
                                : (1 - (accuracy / 40).clamp(0.0, 1.0))
                                      .toDouble(),
                            strokeWidth: 6,
                            backgroundColor: AppColors.surfaceHigh,
                            strokeCap: StrokeCap.round,
                            valueColor: AlwaysStoppedAnimation(
                              ready ? AppColors.blue : AppColors.amber,
                            ),
                          ),
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              ready
                                  ? Icons.gps_fixed_rounded
                                  : Icons.gps_not_fixed_rounded,
                              size: 44,
                              color: ready
                                  ? AppColors.blue
                                  : AppColors.textSecondary,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              accuracy == null
                                  ? '搜索中'
                                  : '±${accuracy.round()} m',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: ready
                                    ? AppColors.blue
                                    : AppColors.textPrimary,
                                fontFeatures: tabularFigures,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 26),
                  Text(
                    ready ? '定位就绪，保持静止' : '正在获取高质量定位…',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    ready
                        ? '车辆保持静止，点击开始后倒计时。'
                        : '精度需要优于 ±${AccelerationRecorder.readyAccuracyM.round()} m，'
                              '请到开阔地带并等待几秒。',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.6,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 26),
                  PressableScale(
                    child: FilledButton.icon(
                      onPressed: ready ? _recorder.startCountdown : null,
                      icon: const Icon(Icons.play_arrow_rounded, size: 22),
                      label: const Text('开始'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextButton(onPressed: _handleBack, child: const Text('取消')),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildReady() {
    final unit = widget.settings.speedUnit;
    return Column(
      children: [
        _TopBar(onClose: _handleBack, title: '就绪'),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              children: [
                Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    color: AppColors.blueSoft,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.blue.withValues(alpha: 0.35),
                      width: 2,
                    ),
                  ),
                  child: const Icon(
                    Icons.gps_fixed_rounded,
                    color: AppColors.blue,
                    size: 36,
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  '准备出发',
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'GPS ±${(_recorder.gpsAccuracyM ?? 0).round()} m · '
                  '目标 ${_formatTarget(unit)}',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 22),
                _TargetCard(
                  targetKmh: _recorder.targetSpeedKmh,
                  unit: unit,
                  rollout: _recorder.rollout,
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.amber.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppColors.amber.withValues(alpha: 0.2),
                    ),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.straighten_rounded,
                        size: 18,
                        color: AppColors.amber,
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '确认车辆已停稳、前方道路笔直且无人无车。开始后请双手握好车把。',
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.6,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                PressableScale(
                  child: FilledButton.icon(
                    onPressed: _recorder.startCountdown,
                    icon: const Icon(Icons.timer_rounded, size: 22),
                    label: const Text('开始测试'),
                  ),
                ),
                const SizedBox(height: 10),
                TextButton(onPressed: _handleBack, child: const Text('取消')),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCountdown() {
    final reduced = AppMotion.reduced(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSwitcher(
            duration: reduced ? AppMotion.fast : AppMotion.med,
            switchInCurve: AppMotion.curve,
            transitionBuilder: (child, animation) {
              final faded = FadeTransition(opacity: animation, child: child);
              if (reduced) {
                return faded;
              }
              return ScaleTransition(
                scale: Tween<double>(begin: 1.3, end: 1).animate(animation),
                child: faded,
              );
            },
            child: Text(
              '${_recorder.countdownRemaining}',
              key: ValueKey(_recorder.countdownRemaining),
              style: displayNumber(
                fontSize: 148,
                letterSpacing: -6,
                color: AppColors.blue,
              ),
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            '准备…',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            '倒计时结束后立即开始计时',
            style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
          ),
          const SizedBox(height: 26),
          OutlinedButton(
            onPressed: _recorder.beginImmediately,
            child: const Text('跳过倒计时'),
          ),
        ],
      ),
    );
  }

  Widget _buildRunning() {
    final unit = widget.settings.speedUnit;
    final speedValue = formatSpeedValue(_recorder.speedMps, unit);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 16, 0),
          child: Row(
            children: [
              IconButton(
                onPressed: _handleBack,
                tooltip: '结束',
                icon: const Icon(Icons.close_rounded),
              ),
              const _LivePill(),
              const Spacer(),
              Text(
                _recorder.gpsOk
                    ? 'GPS ±${(_recorder.gpsAccuracyM ?? 0).round()} m'
                    : 'GPS 信号变差',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: _recorder.gpsOk
                      ? AppColors.textSecondary
                      : AppColors.amber,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _recorder.started
                      ? _recorder.elapsedSeconds.toStringAsFixed(2)
                      : '0.00',
                  style: displayNumber(
                    fontSize: 100,
                    letterSpacing: -5,
                    height: 0.95,
                  ),
                ),
                const Text(
                  '秒',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textTertiary,
                    letterSpacing: 3,
                  ),
                ),
                const SizedBox(height: 22),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      speedValue,
                      style: displayNumber(
                        fontSize: 70,
                        letterSpacing: -3,
                        height: 0.9,
                        color: AppColors.blue,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8, left: 6),
                      child: Text(
                        unit.label,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 26),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: LinearProgressIndicator(
                      value: _recorder.progress,
                      minHeight: 10,
                      backgroundColor: AppColors.surfaceHigh,
                      valueColor: const AlwaysStoppedAnimation(AppColors.blue),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '目标 ${_formatTarget(unit)}'
                  '${_recorder.rollout ? ' · rollout' : ''}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AppColors.divider)),
          ),
          child: FilledButton.icon(
            onPressed: _recorder.finish,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(54),
            ),
            icon: const Icon(Icons.stop_rounded, size: 22),
            label: const Text('结束测试'),
          ),
        ),
      ],
    );
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
            '正在计算成绩…',
            style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildFinished() {
    final result = _recorder.result;
    final unit = widget.settings.speedUnit;
    if (result == null) {
      return Column(
        children: [
          _TopBar(onClose: _handleBack, title: '测试结束'),
          const Expanded(
            child: Center(
              child: Text('没有生成结果', style: TextStyle(fontSize: 16)),
            ),
          ),
        ],
      );
    }

    final seconds = result.resultSeconds;
    final valid = result.valid && seconds != null;
    return Column(
      children: [
        _TopBar(onClose: _handleBack, title: '测试结果'),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              children: [
                if (!valid)
                  _ResultBanner(text: result.invalidReason ?? '成绩未达标，本次不计入记录'),
                const SizedBox(height: 12),
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 1, end: 0),
                  duration: AppMotion.reduced(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 900),
                  curve: AppMotion.curve,
                  builder: (context, glow, child) => Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.blue.withValues(alpha: 0.22 * glow),
                          blurRadius: 44 * glow,
                          spreadRadius: 2 * glow,
                        ),
                      ],
                    ),
                    child: child,
                  ),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                    decoration: cardDecoration(gradient: accelCardGradient),
                    child: Column(
                      children: [
                        Text(
                          _formatTarget(unit),
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
                                seconds == null
                                    ? '—'
                                    : seconds.toStringAsFixed(2),
                                style: displayNumber(
                                  fontSize: 96,
                                  height: 0.95,
                                  letterSpacing: -4,
                                  color: valid
                                      ? AppColors.blue
                                      : AppColors.textTertiary,
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
                        if (_recorder.rollout) ...[
                          const SizedBox(height: 4),
                          const Text(
                            '含 1 英尺 rollout',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _MiniStat(
                        label: '0–60',
                        value: result.result60Ms == null
                            ? '—'
                            : '${(result.result60Ms! / 1000).toStringAsFixed(2)} s',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _MiniStat(
                        label: '60–130',
                        value: result.result130Ms == null
                            ? '—'
                            : '${(result.result130Ms! / 1000).toStringAsFixed(2)} s',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _MiniStat(
                        label: '坡度',
                        value: result.gradePercent == null
                            ? '—'
                            : '${result.gradePercent!.toStringAsFixed(1)}%',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                if (_recorder.savedRunId != null)
                  FilledButton.icon(
                    onPressed: () => _openResult(_recorder.savedRunId!),
                    icon: const Icon(Icons.insights_rounded, size: 20),
                    label: const Text('查看详情'),
                  ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _recorder.prepare,
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                  label: const Text('再测一次'),
                ),
                const SizedBox(height: 8),
                TextButton(onPressed: _handleBack, child: const Text('返回')),
                if (_recorder.errorMessage != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _recorder.errorMessage!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.amber,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFailed() {
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
                  '无法开始测试',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                Text(
                  _recorder.errorMessage ?? '未知错误',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.6,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 26),
                FilledButton.icon(
                  onPressed: _recorder.prepare,
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
                TextButton(onPressed: _handleBack, child: const Text('返回')),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _formatTarget(SpeedUnit unit) {
    final kmh = _recorder.targetSpeedKmh;
    if (unit == SpeedUnit.kmh) {
      return '0–${kmh.round()} km/h';
    }
    final mph = (kmh / 1.609344).round();
    return '0–${kmh.round()} km/h（$mph mph）';
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

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.title,
    required this.body,
    this.danger = false,
  });

  final IconData icon;
  final String title;
  final String body;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.amber : AppColors.blue;
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: cardDecoration(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: const TextStyle(
                    fontSize: 11.5,
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

class _TargetCard extends StatelessWidget {
  const _TargetCard({
    required this.targetKmh,
    required this.unit,
    required this.rollout,
  });

  final double targetKmh;
  final SpeedUnit unit;
  final bool rollout;

  @override
  Widget build(BuildContext context) {
    final mph = (targetKmh / 1.609344).round();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: cardDecoration(color: AppColors.surfaceHigh),
      child: Column(
        children: [
          const Text(
            '本次目标',
            style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
          ),
          const SizedBox(height: 6),
          Text(
            unit == SpeedUnit.kmh
                ? '0 – ${targetKmh.round()} km/h'
                : '0 – $mph mph',
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            rollout ? '含 1 英尺 rollout' : '从静止起算',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: cardDecoration(),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              fontFeatures: tabularFigures,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11.5,
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultBanner extends StatelessWidget {
  const _ResultBanner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.amber.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.amber.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: AppColors.amber,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 11.5,
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

class _LivePill extends StatelessWidget {
  const _LivePill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.25)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 7,
            height: 7,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.danger,
                shape: BoxShape.circle,
              ),
            ),
          ),
          SizedBox(width: 6),
          Text(
            '测试中',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: AppColors.danger,
            ),
          ),
        ],
      ),
    );
  }
}
