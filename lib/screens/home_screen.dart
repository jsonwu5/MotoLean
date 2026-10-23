import 'package:flutter/material.dart';

import '../models/ride_session.dart';
import '../services/demo_ride.dart';
import '../services/ride_store.dart';
import '../theme.dart';
import '../utils/format.dart';
import 'record_screen.dart';
import 'summary_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.store});

  final RideStore store;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<RideSession> _sessions = const [];
  bool _loading = true;
  bool _importingDemo = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() => _loading = true);
    }
    try {
      final sessions = await widget.store.loadSessions();
      if (!mounted) {
        return;
      }
      setState(() {
        _sessions = sessions;
        _loading = false;
        _error = null;
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

  Future<void> _startRide() async {
    final sessionId = await Navigator.of(context).push<int>(
      MaterialPageRoute(
        builder: (_) => RecordScreen(store: widget.store),
      ),
    );
    if (!mounted) {
      return;
    }
    await _load();
    if (sessionId != null && mounted) {
      await _openSummary(sessionId);
    }
  }

  Future<void> _openSummary(int sessionId) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => SummaryScreen(
          store: widget.store,
          sessionId: sessionId,
        ),
      ),
    );
    if (mounted) {
      await _load();
    }
  }

  Future<void> _loadDemo() async {
    if (_importingDemo) {
      return;
    }
    if (_sessions.any((session) => session.isDemo)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已经载入过演示行程，可在列表中查看。')),
      );
      return;
    }
    setState(() => _importingDemo = true);
    try {
      final ride = DemoRideGenerator.build();
      final sessionId = await widget.store.importDemoRide(ride);
      if (!mounted) {
        return;
      }
      await _load();
      if (mounted) {
        await _openSummary(sessionId);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('载入演示行程失败：$error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _importingDemo = false);
      }
    }
  }

  void _showMeasurementInfo() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => const _MeasurementInfoSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalDistance =
        _sessions.fold<double>(0.0, (sum, s) => sum + s.distanceM);
    final maxLean = _sessions.fold<double>(
      0.0,
      (value, s) =>
          value > s.maxLeanLeftDeg && value > s.maxLeanRightDeg
              ? value
              : (s.maxLeanLeftDeg > s.maxLeanRightDeg
                  ? s.maxLeanLeftDeg
                  : s.maxLeanRightDeg),
    );

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(-0.75, -1.05),
            radius: 1.15,
            colors: [
              AppColors.accent.withValues(alpha: 0.09),
              Colors.transparent,
            ],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: RefreshIndicator(
            onRefresh: _load,
            color: AppColors.accent,
            backgroundColor: AppColors.surfaceHigh,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                    child: _Header(onInfo: _showMeasurementInfo),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                    child: _HeroCard(
                      onStart: _startRide,
                      onDemo: _importingDemo ? null : _loadDemo,
                      importingDemo: _importingDemo,
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 30, 20, 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text(
                          '骑行记录',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (_sessions.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceHigh,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '${_sessions.length}',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                        const Spacer(),
                        if (_sessions.isNotEmpty)
                          Text(
                            '${totalDistance >= 1000 ? (totalDistance / 1000).toStringAsFixed(1) : totalDistance.round()} '
                            '${totalDistance >= 1000 ? "km" : "m"} · 最大 ${maxLean.round()}°',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textTertiary,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (_error != null)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: _ErrorCard(message: _error!, onRetry: _load),
                    ),
                  )
                else if (_loading && _sessions.isEmpty)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    ),
                  )
                else if (_sessions.isEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                      child: _EmptyState(
                        onDemo: _importingDemo ? null : _loadDemo,
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    sliver: SliverList.separated(
                      itemCount: _sessions.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final session = _sessions[index];
                        return _SessionCard(
                          session: session,
                          onTap: session.id == null
                              ? null
                              : () => _openSummary(session.id!),
                        );
                      },
                    ),
                  ),
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(28, 28, 28, 36),
                    child: Column(
                      children: [
                        Text(
                          '倾角由手机 IMU 估算，受安装方式、颠簸与路况影响，仅供骑行记录与娱乐参考。\n骑行前完成设置，骑行中请勿操作手机。',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11,
                            height: 1.6,
                            color: AppColors.textTertiary,
                          ),
                        ),
                        SizedBox(height: 10),
                        Text(
                          'MOTOLEAN · 数据保存在本机',
                          style: TextStyle(
                            fontSize: 9,
                            letterSpacing: 2,
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onInfo});

  final VoidCallback onInfo;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: AppColors.accent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(
            Icons.two_wheeler_rounded,
            color: Color(0xFF111400),
            size: 24,
          ),
        ),
        const SizedBox(width: 12),
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '摩倾',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
                height: 1.1,
              ),
            ),
            SizedBox(height: 3),
            Text(
              'MOTOLEAN · 山路记录',
              style: TextStyle(
                fontSize: 9,
                letterSpacing: 1.8,
                fontWeight: FontWeight.w500,
                color: AppColors.textTertiary,
              ),
            ),
          ],
        ),
        const Spacer(),
        IconButton(
          onPressed: onInfo,
          tooltip: '测量说明',
          style: IconButton.styleFrom(
            backgroundColor: AppColors.surface,
            side: const BorderSide(color: AppColors.divider),
          ),
          icon: const Icon(
            Icons.info_outline_rounded,
            size: 20,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.onStart,
    required this.onDemo,
    required this.importingDemo,
  });

  final VoidCallback onStart;
  final VoidCallback? onDemo;
  final bool importingDemo;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF202B0E),
            Color(0xFF151A10),
            Color(0xFF121418),
          ],
          stops: [0, 0.48, 1],
        ),
        border: Border.all(
          color: AppColors.accent.withValues(alpha: 0.14),
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -34,
            bottom: 4,
            child: Transform.rotate(
              angle: -0.35,
              child: Icon(
                Icons.route_rounded,
                size: 190,
                color: AppColors.accent.withValues(alpha: 0.055),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.06),
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.sensors_rounded,
                        size: 12,
                        color: AppColors.accent,
                      ),
                      SizedBox(width: 5),
                      Text(
                        'GPS · IMU · 轨迹',
                        style: TextStyle(
                          fontSize: 9,
                          letterSpacing: 1.1,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  '把每一个弯\n留在记录里。',
                  style: TextStyle(
                    fontSize: 32,
                    height: 1.15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  '倾角、速度、轨迹与海拔，一趟跑山全部记录。',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: onStart,
                  icon: const Icon(Icons.play_arrow_rounded, size: 24),
                  label: const Text('开始记录'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(
                      Icons.straighten_rounded,
                      size: 14,
                      color: AppColors.textTertiary,
                    ),
                    const SizedBox(width: 5),
                    const Expanded(
                      child: Text(
                        '开始前扶正车身，保持静止 3 秒完成校准',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ),
                    if (onDemo != null)
                      TextButton(
                        onPressed: importingDemo ? null : onDemo,
                        style: TextButton.styleFrom(
                          minimumSize: const Size(0, 32),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          foregroundColor: AppColors.textSecondary,
                          textStyle: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        child: importingDemo
                            ? const SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('查看演示'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({required this.session, required this.onTap});

  final RideSession session;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final lean = session.maxLeanLeftDeg > session.maxLeanRightDeg
        ? session.maxLeanLeftDeg
        : session.maxLeanRightDeg;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: cardDecoration(),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 60,
                decoration: BoxDecoration(
                  color: AppColors.surfaceHigh,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      session.startedAt.day.toString().padLeft(2, '0'),
                      style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                        height: 1.05,
                        fontFeatures: tabularFigures,
                      ),
                    ),
                    Text(
                      '${session.startedAt.month}月',
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            formatDateWithWeekday(session.startedAt),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (session.isDemo) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.accentDark,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              '演示',
                              style: TextStyle(
                                fontSize: 8,
                                fontWeight: FontWeight.w700,
                                color: AppColors.accent,
                              ),
                            ),
                          ),
                        ],
                        if (!session.isFinished) ...[
                          const SizedBox(width: 6),
                          const Text(
                            '未完成',
                            style: TextStyle(
                              fontSize: 9,
                              color: AppColors.amber,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${formatClock(session.startedAt)} · ${formatDuration(session.durationS)} · '
                      '均速 ${session.avgSpeedKmh.round()} km/h',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textTertiary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 14,
                      runSpacing: 4,
                      children: [
                        _MiniValue(
                          icon: Icons.route_rounded,
                          value: formatDistance(session.distanceM),
                        ),
                        _MiniValue(
                          icon: Icons.speed_rounded,
                          value: '${session.maxSpeedKmh.round()} km/h',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    lean > 0 ? '${lean.round()}°' : '—',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1,
                      color:
                          lean > 0 ? AppColors.accent : AppColors.textTertiary,
                      fontFeatures: tabularFigures,
                    ),
                  ),
                  const Text(
                    '最大倾角',
                    style: TextStyle(
                      fontSize: 9,
                      letterSpacing: 0.5,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniValue extends StatelessWidget {
  const _MiniValue({required this.icon, required this.value});

  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: AppColors.textTertiary),
        const SizedBox(width: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
            fontFeatures: tabularFigures,
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onDemo});

  final VoidCallback? onDemo;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
      decoration: cardDecoration(),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(
              color: AppColors.surfaceHigh,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.terrain_rounded,
              color: AppColors.accent,
              size: 28,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            '还没有骑行记录',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          const Text(
            '固定好手机，扶正车身，开始第一趟跑山。',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              height: 1.5,
              color: AppColors.textTertiary,
            ),
          ),
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: onDemo,
            icon: const Icon(Icons.play_circle_outline_rounded, size: 18),
            label: const Text('载入演示行程'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(46),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            '没有真机？先看一条模拟山路行程。',
            style: TextStyle(
              fontSize: 10,
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: cardDecoration(color: AppColors.surface),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.danger, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}

class _MeasurementInfoSheet extends StatelessWidget {
  const _MeasurementInfoSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '测量说明',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            const Text(
              '了解这些细节，数据会更可信。',
              style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
            ),
            const SizedBox(height: 22),
            _infoRow(
              Icons.phone_android_rounded,
              '安装方向',
              '手机的 X 轴要指向车身右侧。竖装：屏幕朝向骑手、顶部朝上；平放：屏幕朝上、顶部朝车头。支架必须刚性固定。',
            ),
            _infoRow(
              Icons.straighten_rounded,
              '开始校准',
              '开始记录前扶正车身、保持静止 3 秒。校准的是当前姿态，若支架松动或角度变化，请结束本次记录重新校准。',
            ),
            _infoRow(
              Icons.speed_rounded,
              '精度边界',
              '稳态过弯时倾角误差约 ±1~3°。刹车、颠簸、上下坡和路面横坡都会带来瞬时误差。「最大倾角」请当作趣味数据，不要与专业遥测设备比较。',
            ),
            _infoRow(
              Icons.battery_charging_full_rounded,
              '后台记录',
              'Android 需允许通知与后台定位；iPhone 请把定位权限设为「始终允许」并允许后台活动，否则熄屏后可能停止记录。',
            ),
            _infoRow(
              Icons.health_and_safety_outlined,
              '安全第一',
              '出发前完成全部设置。骑行中不要操作手机，屏幕可保持常亮或熄屏记录。',
            ),
            const SizedBox(height: 8),
            const Divider(),
            const SizedBox(height: 16),
            const Text(
              '注意：手机 GPS 在山谷、林道与隧道中会漂移或中断，轨迹仅供参考。',
              style: TextStyle(
                fontSize: 11,
                height: 1.6,
                color: AppColors.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String title, String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.surfaceHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: AppColors.accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
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
