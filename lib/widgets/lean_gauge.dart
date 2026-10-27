import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';
import '../utils/format.dart';

/// Semicircular lean angle gauge. Positive values are right-hand lean.
///
/// 50 Hz 的原始倾角在 widget 层做短窗阻尼，指针像真仪表一样有惯性地摆动；
/// 左右换向时强调色做渐变过渡而不是硬切。
class LeanGauge extends StatefulWidget {
  const LeanGauge({
    super.key,
    required this.leanDeg,
    this.maxLeftDeg = 0,
    this.maxRightDeg = 0,
    this.height = 232,
  });

  final double leanDeg;
  final double maxLeftDeg;
  final double maxRightDeg;
  final double height;

  @override
  State<LeanGauge> createState() => _LeanGaugeState();
}

class _LeanGaugeState extends State<LeanGauge>
    with SingleTickerProviderStateMixin {
  /// 指针阻尼窗口：足够短以跟上快速压弯，又能吞掉传感器抖动。
  static const _damping = Duration(milliseconds: 90);

  late double _displayedLean = widget.leanDeg;
  late final AnimationController _controller = AnimationController(vsync: this);
  Animation<double> _leanAnimation = const AlwaysStoppedAnimation<double>(0);

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      setState(() => _displayedLean = _leanAnimation.value);
    });
  }

  @override
  void didUpdateWidget(covariant LeanGauge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.leanDeg == widget.leanDeg) {
      return;
    }
    if (AppMotion.reduced(context)) {
      _controller.stop();
      setState(() => _displayedLean = widget.leanDeg);
      return;
    }
    _leanAnimation = Tween<double>(
      begin: _displayedLean,
      end: widget.leanDeg,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.linear));
    _controller
      ..duration = _damping
      ..reset()
      ..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final leanDeg = _displayedLean;
    final leaningRight = leanDeg >= 1;
    final leaningLeft = leanDeg <= -1;
    final targetColor = leaningLeft ? AppColors.blue : AppColors.accent;
    final reduced = AppMotion.reduced(context);
    final direction = leaningRight
        ? '右倾'
        : leaningLeft
        ? '左倾'
        : '直立';

    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: targetColor),
      duration: reduced ? Duration.zero : AppMotion.med,
      curve: AppMotion.curve,
      builder: (context, activeColor, _) {
        final color = activeColor ?? targetColor;
        return SizedBox(
          height: widget.height,
          width: double.infinity,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _GaugePainter(
                    leanDeg: leanDeg,
                    maxLeftDeg: widget.maxLeftDeg,
                    maxRightDeg: widget.maxRightDeg,
                    activeColor: color,
                  ),
                ),
              ),
              Positioned(
                top: widget.height * 0.30,
                left: 0,
                right: 0,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      formatLean(leanDeg),
                      style: TextStyle(
                        fontSize: 52,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -2,
                        height: 1,
                        color: leaningLeft || leaningRight
                            ? color
                            : AppColors.textPrimary,
                        fontFeatures: tabularFigures,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      direction,
                      style: const TextStyle(
                        fontSize: 12,
                        letterSpacing: 4,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                left: 26,
                bottom: 24,
                child: _LimitLabel(
                  label: 'L',
                  value: widget.maxLeftDeg,
                  color: AppColors.blue,
                ),
              ),
              Positioned(
                right: 26,
                bottom: 24,
                child: _LimitLabel(
                  label: 'R',
                  value: widget.maxRightDeg,
                  color: AppColors.accentInk,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LimitLabel extends StatelessWidget {
  const _LimitLabel({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: color.withValues(alpha: 0.9),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          '${value.round()}°',
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.textTertiary,
            fontFeatures: tabularFigures,
          ),
        ),
      ],
    );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter({
    required this.leanDeg,
    required this.maxLeftDeg,
    required this.maxRightDeg,
    required this.activeColor,
  });

  final double leanDeg;
  final double maxLeftDeg;
  final double maxRightDeg;
  final Color activeColor;

  static const double _startDeg = 150;
  static const double _sweepDeg = 240;
  static const double _maxLean = 50;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.63);
    final radius = math.min(size.width / 2 - 30, size.height * 0.52);
    if (radius <= 0) {
      return;
    }
    final rect = Rect.fromCircle(center: center, radius: radius);
    final start = _startDeg * math.pi / 180;
    final sweep = _sweepDeg * math.pi / 180;

    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round
      ..color = AppColors.surfaceHighest;
    canvas.drawArc(rect, start, sweep, false, trackPaint);

    // Ticks every 10 degrees.
    for (var i = 0; i <= 10; i++) {
      final angle = start + sweep * i / 10;
      final isCenter = i == 5;
      final outer =
          center + Offset(math.cos(angle), math.sin(angle)) * (radius - 20);
      final inner =
          center +
          Offset(math.cos(angle), math.sin(angle)) *
              (radius - (isCenter ? 34 : 28));
      canvas.drawLine(
        inner,
        outer,
        Paint()
          ..color = isCenter
              ? AppColors.textSecondary
              : AppColors.textTertiary.withValues(alpha: 0.5)
          ..strokeWidth = isCenter ? 2 : 1.2
          ..strokeCap = StrokeCap.round,
      );
    }

    // Max lean markers.
    _drawMaxMarker(canvas, center, radius, -maxLeftDeg, AppColors.blue);
    _drawMaxMarker(canvas, center, radius, maxRightDeg, AppColors.accentInk);

    // Active arc from upright to current lean.
    final clamped = leanDeg.clamp(-_maxLean, _maxLean).toDouble();
    final centerAngle = start + sweep / 2;
    final valueAngle = centerAngle + (clamped / _maxLean) * (sweep / 2);
    final activeStart = math.min(centerAngle, valueAngle);
    final activeSweep = (valueAngle - centerAngle).abs();

    if (activeSweep > 0.001) {
      final glowPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 13
        ..strokeCap = StrokeCap.round
        ..color = activeColor.withValues(alpha: 0.22)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
      canvas.drawArc(rect, activeStart, activeSweep, false, glowPaint);

      final activePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5.5
        ..strokeCap = StrokeCap.round
        ..color = activeColor;
      canvas.drawArc(rect, activeStart, activeSweep, false, activePaint);
    }

    // Indicator dot.
    final dot =
        center + Offset(math.cos(valueAngle), math.sin(valueAngle)) * radius;
    canvas.drawCircle(
      dot,
      9,
      Paint()..color = activeColor.withValues(alpha: 0.18),
    );
    canvas.drawCircle(dot, 4.5, Paint()..color = activeColor);
  }

  void _drawMaxMarker(
    Canvas canvas,
    Offset center,
    double radius,
    double degrees,
    Color color,
  ) {
    if (degrees.abs() < 3) {
      return;
    }
    final clamped = degrees.clamp(-_maxLean, _maxLean).toDouble();
    final angle =
        (_startDeg + (_sweepDeg / 2) * (1 + clamped / _maxLean)) *
        math.pi /
        180;
    final inner =
        center + Offset(math.cos(angle), math.sin(angle)) * (radius - 9);
    final outer =
        center + Offset(math.cos(angle), math.sin(angle)) * (radius + 9);
    canvas.drawLine(
      inner,
      outer,
      Paint()
        ..color = color.withValues(alpha: 0.85)
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _GaugePainter oldDelegate) =>
      oldDelegate.leanDeg != leanDeg ||
      oldDelegate.maxLeftDeg != maxLeftDeg ||
      oldDelegate.maxRightDeg != maxRightDeg ||
      oldDelegate.activeColor != activeColor;
}
