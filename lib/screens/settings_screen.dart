import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../services/ride_store.dart';
import '../services/settings_service.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../utils/units.dart';
import '../widgets/settings_tile.dart';

/// 当前版本号。发布时与 pubspec.yaml 的 version 同步。
const String kAppVersion = '0.1.0';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.store,
    required this.settings,
  });

  final RideStore store;
  final SettingsService settings;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _busy = false;

  Future<void> _pickSpeedUnit() async {
    final value = await showSettingPicker<SpeedUnit>(
      context,
      title: '速度单位',
      options: const [(SpeedUnit.kmh, 'km/h · 公制'), (SpeedUnit.mph, 'mph · 英制')],
      current: widget.settings.speedUnit,
    );
    if (value != null) {
      await widget.settings.setSpeedUnit(value);
    }
  }

  Future<void> _pickDistanceUnit() async {
    final value = await showSettingPicker<DistanceUnit>(
      context,
      title: '距离单位',
      options: const [(DistanceUnit.km, 'km · 公制'), (DistanceUnit.mi, 'mi · 英制')],
      current: widget.settings.distanceUnit,
    );
    if (value != null) {
      await widget.settings.setDistanceUnit(value);
    }
  }

  Future<void> _pickCalibration() async {
    final value = await showSettingPicker<int>(
      context,
      title: '校准时长',
      options: const [(2, '2 秒'), (3, '3 秒（推荐）'), (5, '5 秒')],
      current: widget.settings.calibrationSeconds,
    );
    if (value != null) {
      await widget.settings.setCalibrationSeconds(value);
    }
  }

  Future<void> _pickGpsAccuracy() async {
    var value = widget.settings.gpsAccuracyLimit;
    final confirmed = await showDialog<double>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('GPS 精度阈值'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '精度差于 ±${value.round()} m 的采样点会被丢弃。'
                '阈值越严数据越干净，但弱信号路段可能采不到点。',
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              Slider(
                value: value,
                min: 10,
                max: 50,
                divisions: 8,
                label: '±${value.round()} m',
                activeColor: AppColors.accent,
                onChanged: (next) =>
                    setDialogState(() => value = next),
              ),
              Center(
                child: Text(
                  '±${value.round()} m',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(value),
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 44),
                padding: const EdgeInsets.symmetric(horizontal: 18),
              ),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != null) {
      await widget.settings.setGpsAccuracyLimit(confirmed);
    }
  }

  Future<void> _pickAccelTarget() async {
    final value = await showSettingPicker<double>(
      context,
      title: '默认目标速度',
      options: const [
        (60.0, '0–60 km/h'),
        (100.0, '0–100 km/h（推荐）'),
        (200.0, '0–200 km/h'),
      ],
      current: widget.settings.accelTargetSpeedKmh,
    );
    if (value != null) {
      await widget.settings.setAccelTargetSpeedKmh(value);
    }
  }

  Future<void> _pickAccelCountdown() async {
    final value = await showSettingPicker<int>(
      context,
      title: '起步倒计时',
      options: const [(0, '关闭 · 点击立即开始'), (3, '3 秒倒计时')],
      current: widget.settings.accelCountdownSeconds,
    );
    if (value != null) {
      await widget.settings.setAccelCountdownSeconds(value);
    }
  }

  Future<void> _pickMapStyle() async {
    final value = await showSettingPicker<MapStyle>(
      context,
      title: '地图底图',
      options: const [
        (MapStyle.satellite, '卫星影像 · Esri'),
        (MapStyle.dark, '简约暗色'),
      ],
      current: widget.settings.mapStyle,
    );
    if (value != null) {
      await widget.settings.setMapStyle(value);
    }
  }

  Future<void> _exportAll() async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      final sessions = await widget.store.loadSessions();
      if (sessions.isEmpty) {
        _snack('还没有骑行记录可以导出');
        return;
      }
      final buffer = StringBuffer('\uFEFF');
      buffer.writeln(
        'session_id,started_at,is_demo,t_ms,lat,lon,altitude_m,speed_kmh,lean_deg,accuracy_m',
      );
      var rows = 0;
      for (final session in sessions) {
        final id = session.id;
        if (id == null) {
          continue;
        }
        final samples = await widget.store.loadSamples(id);
        final started = session.startedAt.toUtc().toIso8601String();
        for (final sample in samples) {
          buffer.writeln([
            id,
            started,
            session.isDemo ? 1 : 0,
            sample.tMs,
            sample.lat?.toStringAsFixed(7) ?? '',
            sample.lon?.toStringAsFixed(7) ?? '',
            sample.altitudeM?.toStringAsFixed(1) ?? '',
            sample.speedKmh?.toStringAsFixed(1) ?? '',
            sample.leanDeg.toStringAsFixed(1),
            sample.accuracyM?.toStringAsFixed(1) ?? '',
          ].join(','));
          rows++;
        }
      }
      if (rows == 0) {
        _snack('记录里没有采样点');
        return;
      }
      final file = XFile.fromData(
        utf8.encode(buffer.toString()),
        mimeType: 'text/csv',
        name: 'motolean_all_${formatFileStamp(DateTime.now())}.csv',
      );
      await SharePlus.instance.share(
        ShareParams(
          files: [file],
          subject: '摩倾全部骑行数据',
          text: '共 ${sessions.length} 条行程、$rows 个采样点',
        ),
      );
    } catch (error) {
      _snack('导出失败：$error');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _confirmClearRides() async {
    final confirmed = await _confirmDanger(
      title: '清空全部骑行记录？',
      body: '所有行程、采样点与演示数据将被永久删除，无法恢复。建议先导出数据。',
      confirmLabel: '全部删除',
    );
    if (confirmed != true) {
      return;
    }
    try {
      await widget.store.deleteAllRides();
      _snack('已清空全部骑行记录');
    } catch (error) {
      _snack('清空失败：$error');
    }
  }

  Future<void> _confirmClearRuns() async {
    final confirmed = await _confirmDanger(
      title: '清空全部加速成绩？',
      body: '所有零百成绩与采样数据将被永久删除，无法恢复。',
      confirmLabel: '全部删除',
    );
    if (confirmed != true) {
      return;
    }
    try {
      await widget.store.deleteAllAccelerationRuns();
      _snack('已清空全部加速成绩');
    } catch (error) {
      _snack('清空失败：$error');
    }
  }

  Future<void> _confirmClearDemo() async {
    final confirmed = await _confirmDanger(
      title: '清除演示数据？',
      body: '会删除标记为「演示」的行程与成绩，真实数据不受影响。',
      confirmLabel: '清除演示',
      danger: false,
    );
    if (confirmed != true) {
      return;
    }
    try {
      await widget.store.deleteDemoData();
      _snack('已清除演示数据');
    } catch (error) {
      _snack('清除失败：$error');
    }
  }

  Future<void> _confirmReset() async {
    final confirmed = await _confirmDanger(
      title: '恢复默认设置？',
      body: '单位、记录、零百与地图设置都会回到默认值。骑行记录与成绩不受影响。',
      confirmLabel: '恢复默认',
      danger: false,
    );
    if (confirmed != true) {
      return;
    }
    await widget.settings.resetToDefaults();
    _snack('已恢复默认设置');
  }

  Future<bool?> _confirmDanger({
    required String title,
    required String body,
    required String confirmLabel,
    bool danger = true,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: danger ? AppColors.danger : AppColors.accent,
              foregroundColor: danger ? Colors.white : const Color(0xFF101400),
              minimumSize: const Size(0, 44),
              padding: const EdgeInsets.symmetric(horizontal: 18),
            ),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  }

  void _snack(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _showAbout() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('关于摩倾'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '摩倾 MotoLean',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 2),
            Text(
              '版本 $kAppVersion',
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textTertiary,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '记录摩托车跑山时的倾角、速度、轨迹与海拔，并提供零百加速测试。'
              '所有数据仅保存在本机，不上传云端，不含账号体系。',
              style: TextStyle(
                fontSize: 12,
                height: 1.6,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '倾角由手机 IMU 估算，零百成绩由 GPS 插值估算，均受设备与安装方式影响，'
              '仅供记录与娱乐参考，不构成任何安全保证。',
              style: TextStyle(
                fontSize: 11,
                height: 1.6,
                color: AppColors.textTertiary,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  void _showPrivacy() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('隐私说明'),
        content: const Text(
          '1. 本应用不收集、不上传任何个人信息，没有账号与云端同步。\n'
          '2. 骑行轨迹、倾角与加速成绩只写入手机应用私有目录的数据库。\n'
          '3. 地图底图来自 Esri 在线瓦片，加载地图时会向地图服务商暴露你正在查看的区域；'
          '不使用地图时可完全离线。\n'
          '4. 导出 GPX/CSV 通过系统分享面板完成，文件由你自行决定发给谁。\n'
          '5. 卸载应用会删除全部本地数据。',
          style: TextStyle(fontSize: 12.5, height: 1.7),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  void _showMeasurement() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('测量说明'),
        content: const Text(
          '倾角：加速度计 + 陀螺仪互补滤波，稳态过弯误差约 ±1–3°。\n\n'
          '零百加速：GPS 多普勒测速，更新率约 1 Hz，通过相邻采样点插值计算达速时刻，'
          '成绩误差约 ±0.1–0.3 秒。\n\n'
          '坡度与距离由定位数据推算，长距离下会有累积误差。',
          style: TextStyle(fontSize: 12.5, height: 1.7),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('设置'),
      ),
      body: AnimatedBuilder(
        animation: widget.settings,
        builder: (context, _) {
          final settings = widget.settings;
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
            children: [
              SettingsSection(
                title: '单位',
                children: [
                  SettingsChoiceTile(
                    icon: Icons.speed_rounded,
                    title: '速度',
                    value: settings.speedUnit.label,
                    onTap: _pickSpeedUnit,
                  ),
                  SettingsChoiceTile(
                    icon: Icons.route_rounded,
                    title: '距离',
                    value: settings.distanceUnit.label,
                    onTap: _pickDistanceUnit,
                  ),
                ],
              ),
              SettingsSection(
                title: '记录',
                children: [
                  SettingsChoiceTile(
                    icon: Icons.timer_rounded,
                    title: '校准时长',
                    subtitle: '开始记录前保持静止的时间',
                    value: '${settings.calibrationSeconds} 秒',
                    onTap: _pickCalibration,
                  ),
                  SettingsChoiceTile(
                    icon: Icons.gps_fixed_rounded,
                    title: 'GPS 精度阈值',
                    subtitle: '差于此值的采样点会被丢弃',
                    value: '±${settings.gpsAccuracyLimit.round()} m',
                    onTap: _pickGpsAccuracy,
                  ),
                  SettingsSwitchTile(
                    icon: Icons.light_mode_rounded,
                    title: '默认屏幕常亮',
                    subtitle: '进入记录页时自动开启',
                    value: settings.defaultScreenAwake,
                    onChanged: settings.setDefaultScreenAwake,
                  ),
                  SettingsSwitchTile(
                    icon: Icons.help_outline_rounded,
                    title: '结束前二次确认',
                    subtitle: '防止骑行中误触结束记录',
                    value: settings.confirmBeforeStop,
                    onChanged: settings.setConfirmBeforeStop,
                  ),
                ],
              ),
              SettingsSection(
                title: '零百加速',
                children: [
                  SettingsChoiceTile(
                    icon: Icons.flag_rounded,
                    title: '默认目标速度',
                    value: '${settings.accelTargetSpeedKmh.round()} km/h',
                    onTap: _pickAccelTarget,
                  ),
                  SettingsSwitchTile(
                    icon: Icons.straighten_rounded,
                    title: '1 英尺 rollout',
                    subtitle: '从车辆移动约 30 cm 后开始计时，成绩更短',
                    value: settings.accelRollout,
                    onChanged: settings.setAccelRollout,
                  ),
                  SettingsChoiceTile(
                    icon: Icons.hourglass_bottom_rounded,
                    title: '起步倒计时',
                    value: settings.accelCountdownSeconds == 0
                        ? '关闭'
                        : '${settings.accelCountdownSeconds} 秒',
                    onTap: _pickAccelCountdown,
                  ),
                  SettingsSwitchTile(
                    icon: Icons.pin_drop_rounded,
                    title: '记录测试轨迹',
                    subtitle: '关闭后只记录速度与时间，更省电',
                    value: settings.accelRecordTrack,
                    onChanged: settings.setAccelRecordTrack,
                  ),
                ],
              ),
              SettingsSection(
                title: '地图',
                children: [
                  SettingsSwitchTile(
                    icon: Icons.layers_rounded,
                    title: '显示实时轨迹',
                    subtitle: '记录页显示跟随地图',
                    value: settings.showLiveTrack,
                    onChanged: settings.setShowLiveTrack,
                  ),
                  SettingsChoiceTile(
                    icon: Icons.map_rounded,
                    title: '底图',
                    value: settings.mapStyle.label,
                    onTap: _pickMapStyle,
                  ),
                ],
              ),
              SettingsSection(
                title: '数据',
                children: [
                  SettingsTile(
                    icon: Icons.ios_share_rounded,
                    title: '导出全部骑行数据',
                    subtitle: _busy ? '正在生成…' : '合并为一个 CSV 文件',
                    onTap: _busy ? null : _exportAll,
                  ),
                  SettingsTile(
                    icon: Icons.auto_delete_outlined,
                    title: '清除演示数据',
                    subtitle: '只删除标记为演示的行程与成绩',
                    onTap: _confirmClearDemo,
                  ),
                  SettingsTile(
                    icon: Icons.delete_sweep_rounded,
                    title: '清空全部加速成绩',
                    onTap: _confirmClearRuns,
                    danger: true,
                  ),
                  SettingsTile(
                    icon: Icons.delete_forever_rounded,
                    title: '清空全部骑行记录',
                    onTap: _confirmClearRides,
                    danger: true,
                  ),
                  SettingsTile(
                    icon: Icons.restart_alt_rounded,
                    title: '恢复默认设置',
                    onTap: _confirmReset,
                  ),
                ],
              ),
              SettingsSection(
                title: '关于',
                children: [
                  SettingsTile(
                    icon: Icons.info_outline_rounded,
                    title: '关于摩倾',
                    subtitle: '版本 $kAppVersion',
                    onTap: _showAbout,
                  ),
                  SettingsTile(
                    icon: Icons.shield_outlined,
                    title: '隐私说明',
                    subtitle: '数据只存在本机',
                    onTap: _showPrivacy,
                  ),
                  SettingsTile(
                    icon: Icons.straighten_rounded,
                    title: '测量说明',
                    subtitle: '倾角与加速成绩的精度边界',
                    onTap: _showMeasurement,
                  ),
                ],
              ),
              const Text(
                'MOTOLEAN · 数据保存在本机',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 9,
                  letterSpacing: 2,
                  color: AppColors.textTertiary,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
