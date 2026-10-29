import 'package:flutter/material.dart';

import '../theme.dart';
import 'motion.dart';

class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.accent = false,
    this.height = 88,
    this.countUp,
    this.countFormat,
  });

  final String label;
  final String value;
  final String? unit;
  final bool accent;
  final double height;

  /// 提供时数值从 0 滚动到该值，用 [countFormat] 格式化。仅用于总结页这类
  /// 一次性展示的静态数据；实时页面不要开启。
  final double? countUp;
  final String Function(double value)? countFormat;

  @override
  Widget build(BuildContext context) {
    final valueStyle = TextStyle(
      fontSize: 24,
      fontWeight: FontWeight.w800,
      height: 1.1,
      letterSpacing: -0.8,
      color: accent ? AppColors.accentInk : AppColors.textPrimary,
      fontFeatures: tabularFigures,
    );
    final animatable = countUp != null && countFormat != null;
    return Container(
      height: height,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: cardDecoration(color: AppColors.surface),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
              color: AppColors.textTertiary,
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: animatable
                    ? CountUpText(
                        value: countUp!,
                        format: countFormat!,
                        style: valueStyle,
                      )
                    : Text(
                        value,
                        maxLines: 1,
                        overflow: TextOverflow.fade,
                        softWrap: false,
                        style: valueStyle,
                      ),
              ),
              if (unit != null) ...[
                const SizedBox(width: 4),
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    unit!,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textTertiary,
                    ),
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
