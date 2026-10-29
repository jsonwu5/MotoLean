import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// 品牌 logomark：青蓝圆角方块上的倾角表盘弧线与右倾指针。
///
/// 直接取自核心组件 [LeanGauge] 的视觉语言——这是 App 的第一隐喻。
/// 用于首页头部、关于页、分享海报等品牌触点。
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 42, this.radius = 14});

  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.accent,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: CustomPaint(painter: _BrandMarkPainter()),
    );
  }
}

class _BrandMarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final side = math.min(size.width, size.height);
    final center = Offset(size.width / 2, size.height * 0.62);
    final radius = side * 0.30;

    // 表盘弧线：与 LeanGauge 相同的 240° 扫掠。
    final rect = Rect.fromCircle(center: center, radius: radius);
    const startDeg = 150.0;
    const sweepDeg = 240.0;
    final start = startDeg * math.pi / 180;
    final sweep = sweepDeg * math.pi / 180;

    canvas.drawArc(
      rect,
      start,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = side * 0.075
        ..strokeCap = StrokeCap.round
        ..color = AppColors.onAccent.withValues(alpha: 0.35),
    );

    // 指针：指向右倾约 32°，像正在压弯。
    const needleLean = 32.0;
    final valueAngle =
        (startDeg + sweepDeg / 2 + (needleLean / 50) * (sweepDeg / 2)) *
        math.pi /
        180;
    final tip =
        center + Offset(math.cos(valueAngle), math.sin(valueAngle)) * radius;
    canvas.drawLine(
      center,
      tip,
      Paint()
        ..color = AppColors.onAccent
        ..strokeWidth = side * 0.06
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(center, side * 0.075, Paint()..color = AppColors.onAccent);
    canvas.drawCircle(tip, side * 0.045, Paint()..color = AppColors.onAccent);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
