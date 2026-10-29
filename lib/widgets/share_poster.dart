import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/acceleration_run.dart';
import '../models/ride_session.dart';
import '../services/settings_service.dart';
import '../services/share_image.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../utils/ride_analytics.dart';
import '../utils/units.dart';
import 'brand_mark.dart';
import 'ride_map.dart' show leanColor;

/// 海报按固定逻辑宽度排版，导出时统一放大 3 倍，得到约 1080px 宽的长图。
const double kSharePosterWidth = 360;

/// 打开长图预览弹窗。
///
/// 保存成功时返回 true：调用方可以据此提示，或引导用户去社交 App 选图。
Future<bool?> showSharePosterDialog(
  BuildContext context, {
  required Widget poster,
  required String fileName,
  String? subject,
  String? text,
}) {
  return showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.5),
    builder: (_) => _SharePosterDialog(
      poster: poster,
      fileName: fileName,
      subject: subject,
      text: text,
    ),
  );
}

class _SharePosterDialog extends StatefulWidget {
  const _SharePosterDialog({
    required this.poster,
    required this.fileName,
    this.subject,
    this.text,
  });

  final Widget poster;
  final String fileName;
  final String? subject;
  final String? text;

  @override
  State<_SharePosterDialog> createState() => _SharePosterDialogState();
}

class _SharePosterDialogState extends State<_SharePosterDialog> {
  final GlobalKey _boundaryKey = GlobalKey();
  final GlobalKey _shareButtonKey = GlobalKey();
  bool _busy = false;
  String? _error;

  /// 相册里使用的文件名（不带扩展名）。
  String get _galleryName {
    final dot = widget.fileName.lastIndexOf('.');
    return dot <= 0 ? widget.fileName : widget.fileName.substring(0, dot);
  }

  Future<void> _saveToGallery() async {
    if (_busy) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final png = await ShareImage.capture(_boundaryKey);
      await ShareImage.saveToGallery(png, name: _galleryName);
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$error';
        });
      }
    }
  }

  Future<void> _share() async {
    if (_busy) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final png = await ShareImage.capture(_boundaryKey);
      final box =
          _shareButtonKey.currentContext?.findRenderObject() as RenderBox?;
      final origin = box == null
          ? null
          : box.localToGlobal(Offset.zero) & box.size;
      await ShareImage.share(
        png: png,
        fileName: widget.fileName,
        subject: widget.subject,
        text: widget.text,
        sharePositionOrigin: origin,
      );
      if (mounted) {
        setState(() => _busy = false);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$error';
        });
      }
    }
  }

  Future<void> _copyCaption() async {
    final caption = widget.text?.trim();
    if (caption == null || caption.isEmpty) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: caption));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('文案已复制')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.52;
    return Dialog(
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Text(
                      '保存长图',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: _busy
                          ? null
                          : () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded, size: 20),
                      tooltip: '关闭',
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: maxHeight),
                  child: FittedBox(
                    fit: BoxFit.contain,
                    child: RepaintBoundary(
                      key: _boundaryKey,
                      child: MediaQuery.withNoTextScaling(child: widget.poster),
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _error!,
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: AppColors.danger,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                FilledButton.icon(
                  key: _shareButtonKey,
                  onPressed: _busy ? null : _saveToGallery,
                  icon: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.download_rounded, size: 20),
                  label: Text(_busy ? '正在保存…' : '保存到相册'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _share,
                  icon: const Icon(Icons.ios_share_rounded, size: 18),
                  label: const Text('更多分享方式'),
                ),
                if (widget.text != null && widget.text!.trim().isNotEmpty)
                  Center(
                    child: TextButton.icon(
                      onPressed: _busy ? null : _copyCaption,
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      label: const Text('复制文案'),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, 40),
                      ),
                    ),
                  ),
                const SizedBox(height: 2),
                const Text(
                  '保存后可在微信、抖音、小红书等 App 中直接选图发布',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.5,
                    color: AppColors.textTertiary,
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

/// 海报通用外框：白底 + 顶部淡青雾，与 App 内视觉一致。
class _PosterShell extends StatelessWidget {
  const _PosterShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: kSharePosterWidth,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.background, AppColors.surface],
          stops: [0, 0.32],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      child: child,
    );
  }
}

class _PosterHeader extends StatelessWidget {
  const _PosterHeader({required this.startedAt});

  final DateTime startedAt;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const BrandMark(size: 34, radius: 11),
        const SizedBox(width: 10),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '摩倾',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'MOTOLEAN · 山路记录',
                style: TextStyle(
                  fontSize: 9,
                  letterSpacing: 1.1,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textTertiary,
                ),
              ),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              formatDateWithWeekday(startedAt),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              formatClock(startedAt),
              style: const TextStyle(
                fontSize: 10,
                color: AppColors.textTertiary,
                fontFeatures: tabularFigures,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PosterFooter extends StatelessWidget {
  const _PosterFooter({required this.note});

  final String note;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Divider(color: AppColors.divider, height: 1),
        const SizedBox(height: 12),
        Text(
          note,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 9.5,
            height: 1.6,
            color: AppColors.textTertiary,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'MOTOLEAN · 数据保存在本机',
          style: TextStyle(
            fontSize: 9,
            letterSpacing: 1.6,
            fontWeight: FontWeight.w600,
            color: AppColors.textTertiary,
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w800,
        color: AppColors.textSecondary,
        letterSpacing: 0.3,
      ),
    );
  }
}

/// 主数据卡：淡青渐变 + 大字号数值；[blue] 时切换为加速域的蓝色叙事。
class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.label,
    required this.value,
    required this.unit,
    required this.chips,
    this.blue = false,
  });

  final String label;
  final String value;
  final String unit;
  final bool blue;

  /// 底部一行小指标：(标签, 数值)
  final List<(String, String)> chips;

  @override
  Widget build(BuildContext context) {
    final domainColor = blue ? AppColors.blue : AppColors.accent;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        gradient: blue
            ? accelCardGradient
            : const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFDFF3F6), Color(0xFFF7FBFC)],
              ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: domainColor.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: blue ? AppColors.blue : AppColors.accentInk,
            ),
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  value,
                  style: displayNumber(fontSize: 50, letterSpacing: -2),
                ),
                const SizedBox(width: 6),
                Text(
                  unit,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(height: 1, color: domainColor.withValues(alpha: 0.18)),
          const SizedBox(height: 10),
          Row(
            children: [
              for (var i = 0; i < chips.length; i++) ...[
                if (i > 0)
                  Container(
                    width: 1,
                    height: 22,
                    margin: const EdgeInsets.symmetric(horizontal: 10),
                    color: AppColors.divider,
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        chips[i].$1,
                        style: const TextStyle(
                          fontSize: 9.5,
                          color: AppColors.textTertiary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        chips[i].$2,
                        style: displayNumber(fontSize: 14, slanted: false),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _LeanTile extends StatelessWidget {
  const _LeanTile({
    required this.label,
    required this.degrees,
    required this.color,
  });

  final String label;
  final double degrees;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: AppColors.textTertiary,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                degrees <= 0 ? '—' : degrees.round().toString(),
                style: displayNumber(
                  fontSize: 33,
                  letterSpacing: -1,
                  color: degrees <= 0 ? AppColors.textTertiary : color,
                ),
              ),
              const SizedBox(width: 2),
              Text(
                '°',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: color.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({
    required this.label,
    required this.value,
    this.icon,
    this.iconColor = AppColors.accentInk,
  });

  final String label;
  final String value;
  final IconData? icon;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: iconColor),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 9.5,
                    color: AppColors.textTertiary,
                  ),
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: displayNumber(fontSize: 15, slanted: false),
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

class _BandBar extends StatelessWidget {
  const _BandBar({
    required this.label,
    required this.fraction,
    required this.seconds,
    required this.color,
  });

  final String label;
  final double fraction;
  final int seconds;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        children: [
          SizedBox(
            width: 52,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Container(
                height: 7,
                color: AppColors.surfaceHighest,
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: fraction.clamp(0.0, 1.0),
                  child: Container(color: color),
                ),
              ),
            ),
          ),
          SizedBox(
            width: 62,
            child: Text(
              '${(fraction * 100).round()}% · ${formatDuration(seconds)}',
              textAlign: TextAlign.right,
              maxLines: 1,
              style: const TextStyle(
                fontSize: 9.5,
                color: AppColors.textTertiary,
                fontFeatures: tabularFigures,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 行程总结长图。
class RideSharePoster extends StatelessWidget {
  const RideSharePoster({
    super.key,
    required this.session,
    required this.bands,
    required this.corners,
    required this.settings,
  });

  final RideSession session;
  final List<LeanBandStat> bands;
  final int corners;
  final SettingsService settings;

  @override
  Widget build(BuildContext context) {
    final distanceUnit = settings.distanceUnit;
    final speedUnit = settings.speedUnit;

    return _PosterShell(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PosterHeader(startedAt: session.startedAt),
          const SizedBox(height: 16),
          _HeroCard(
            label: '本次骑行 · 里程',
            value: formatDistanceValue(session.distanceM, distanceUnit),
            unit: distanceValueLabel(session.distanceM, distanceUnit),
            chips: [
              ('时长', formatDuration(session.durationS)),
              ('均速', formatSpeedWithUnit(session.avgSpeedMps, speedUnit)),
              ('极速', formatSpeedWithUnit(session.maxSpeedMps, speedUnit)),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _LeanTile(
                  label: '最大左倾',
                  degrees: session.maxLeanLeftDeg,
                  color: AppColors.blue,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _LeanTile(
                  label: '最大右倾',
                  degrees: session.maxLeanRightDeg,
                  color: AppColors.accentInk,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _StatCell(
                  label: '累计爬升',
                  value: formatElevationWithUnit(
                    session.elevationGainM,
                    settings.elevationUnit,
                  ),
                  icon: Icons.terrain_rounded,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _StatCell(
                  label: '过弯次数',
                  value: '$corners 次',
                  icon: Icons.turn_right_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const _SectionTitle('倾角分布'),
          const SizedBox(height: 8),
          for (final band in bands)
            _BandBar(
              label: band.label,
              fraction: band.fraction,
              seconds: band.seconds,
              color: band.lowerDeg == 0
                  ? AppColors.textTertiary
                  : leanColor((band.lowerDeg + band.upperDeg) / 2),
            ),
          const SizedBox(height: 10),
          const _PosterFooter(note: '倾角由手机 IMU 估算，速度与轨迹来自 GPS，仅供骑行记录与参考。'),
        ],
      ),
    );
  }
}

/// 零百加速成绩长图。
class AccelerationSharePoster extends StatelessWidget {
  const AccelerationSharePoster({
    super.key,
    required this.run,
    required this.settings,
  });

  final AccelerationRun run;
  final SettingsService settings;

  String _seconds(int? ms) =>
      ms == null ? '—' : '${(ms / 1000).toStringAsFixed(2)} s';

  @override
  Widget build(BuildContext context) {
    final cells = <(String, String, IconData)>[
      if (run.result60Ms != null)
        ('0–60 km/h', _seconds(run.result60Ms), Icons.bolt_rounded),
      if (run.result130Ms != null)
        ('60–130 km/h', _seconds(run.result130Ms), Icons.speed_rounded),
      (
        '起步距离',
        run.distanceM == null
            ? '—'
            : formatDistanceWithUnit(run.distanceM!, settings.distanceUnit),
        Icons.straighten_rounded,
      ),
      (
        '坡度',
        run.gradePercent == null
            ? '—'
            : '${run.gradePercent!.toStringAsFixed(1)}%',
        Icons.landscape_rounded,
      ),
      (
        'GPS 精度',
        run.gpsAccuracyM == null ? '—' : '±${run.gpsAccuracyM!.round()} m',
        Icons.gps_fixed_rounded,
      ),
      (
        '最高速度',
        run.maxSpeedKmh == null
            ? '—'
            : formatSpeedWithUnit(run.maxSpeedKmh! / 3.6, settings.speedUnit),
        Icons.speed_rounded,
      ),
    ];

    return _PosterShell(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PosterHeader(startedAt: run.startedAt),
          const SizedBox(height: 16),
          _HeroCard(
            label: run.rollout
                ? '0–${run.targetSpeedKmh.round()} km/h · 含 1 英尺 rollout'
                : '0–${run.targetSpeedKmh.round()} km/h',
            value: (run.resultMs / 1000).toStringAsFixed(2),
            unit: 's',
            blue: true,
            chips: [
              ('目标', '${run.targetSpeedKmh.round()} km/h'),
              ('口径', run.rollout ? '1 英尺' : '静止'),
              ('状态', run.valid ? '有效' : '数据不足'),
            ],
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < cells.length; i += 2) ...[
            Row(
              children: [
                Expanded(
                  child: _StatCell(
                    label: cells[i].$1,
                    value: cells[i].$2,
                    icon: cells[i].$3,
                    iconColor: AppColors.blue,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: i + 1 < cells.length
                      ? _StatCell(
                          label: cells[i + 1].$1,
                          value: cells[i + 1].$2,
                          icon: cells[i + 1].$3,
                          iconColor: AppColors.blue,
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 4),
          const _PosterFooter(note: '成绩由手机 GPS 测速插值计算，适合同一设备横向对比，仅供参考。'),
        ],
      ),
    );
  }
}
