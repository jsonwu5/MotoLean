import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/ride_sample.dart';
import '../services/settings_service.dart';
import '../theme.dart';
import '../widgets/ride_playback_map.dart';

/// 全屏沉浸式轨迹回放：地图铺满屏幕，控件浮在画面之上。
class TrackPlaybackScreen extends StatelessWidget {
  const TrackPlaybackScreen({
    super.key,
    required this.samples,
    required this.settings,
    this.title = '轨迹回放',
    this.subtitle,
  });

  final List<RideSample> samples;
  final SettingsService settings;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final points = buildPlaybackPoints(samples);
    final padding = MediaQuery.paddingOf(context);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            Positioned.fill(
              child: RidePlaybackMap(
                points: points,
                initialStyle: settings.mapStyle,
                speedUnit: settings.speedUnit,
                topInset: padding.top + 56,
                bottomInset: padding.bottom,
              ),
            ),
            Positioned(
              top: padding.top + 8,
              left: 14,
              right: 14,
              child: _TopBar(
                title: title,
                subtitle: subtitle,
                duration: points.isEmpty
                    ? null
                    : Duration(milliseconds: points.last.tMs),
                onBack: () => Navigator.of(context).maybePop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.title,
    required this.onBack,
    this.subtitle,
    this.duration,
  });

  final String title;
  final String? subtitle;
  final Duration? duration;
  final VoidCallback onBack;

  String get _durationLabel {
    final d = duration;
    if (d == null) {
      return '';
    }
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  static const _shadow = <Shadow>[
    Shadow(color: Color(0x66000000), blurRadius: 10, offset: Offset(0, 1)),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // 只有按钮本身有底色，整体不再是胶囊条
        Material(
          color: Colors.black.withValues(alpha: 0.32),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onBack,
            child: const SizedBox(
              width: 38,
              height: 38,
              child: Icon(
                Icons.arrow_back_rounded,
                size: 20,
                color: Colors.white,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 17,
                  height: 1.1,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2,
                  color: Colors.white,
                  shadows: _shadow,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 3),
                Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.1,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withValues(alpha: 0.82),
                    shadows: _shadow,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (duration != null) ...[
          const SizedBox(width: 10),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.schedule_rounded,
                size: 13,
                color: Colors.white.withValues(alpha: 0.8),
              ),
              const SizedBox(width: 4),
              Text(
                _durationLabel,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.white.withValues(alpha: 0.92),
                  fontFeatures: tabularFigures,
                  shadows: _shadow,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
