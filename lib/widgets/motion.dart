import 'package:flutter/material.dart';

import '../theme.dart';

/// 按压缩放反馈：按下时轻微缩小，松开回弹。
///
/// 用 [Listener] 而不是手势识别器实现，避免抢占按钮自身的点击手势。
class PressableScale extends StatefulWidget {
  const PressableScale({super.key, required this.child});

  final Widget child;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (value == _pressed || !mounted) {
      return;
    }
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final reduced = AppMotion.reduced(context);
    return Listener(
      onPointerDown: (_) => _setPressed(true),
      onPointerUp: (_) => _setPressed(false),
      onPointerCancel: (_) => _setPressed(false),
      child: AnimatedScale(
        scale: _pressed && !reduced ? 0.97 : 1,
        duration: AppMotion.fast,
        curve: AppMotion.curve,
        child: widget.child,
      ),
    );
  }
}

/// 入场动画：按列表顺序错峰淡入并轻微上移。
///
/// [index] 决定延迟，越靠后的元素越晚出现；系统开启「减弱动态效果」时
/// 直接显示最终状态，不播放动画。
class StaggerIn extends StatefulWidget {
  const StaggerIn({
    super.key,
    required this.index,
    required this.child,
    this.maxDelayMs = 420,
  });

  final int index;
  final Widget child;
  final int maxDelayMs;

  @override
  State<StaggerIn> createState() => _StaggerInState();
}

class _StaggerInState extends State<StaggerIn>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  double _intervalStart = 0;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) {
      return;
    }
    _started = true;
    if (AppMotion.reduced(context)) {
      return;
    }
    final delayMs =
        (widget.index.clamp(0, 12) * 55).clamp(0, widget.maxDelayMs);
    final totalMs = delayMs + AppMotion.slow.inMilliseconds;
    _intervalStart = delayMs / totalMs;
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: totalMs),
    )..forward();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return widget.child;
    }
    // 用 Interval 表达「延迟 + 播放」，避免 Timer 在测试结束前悬挂。
    final curved = CurvedAnimation(
      parent: controller,
      curve: Interval(_intervalStart, 1, curve: AppMotion.curve),
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.045),
          end: Offset.zero,
        ).animate(curved),
        child: widget.child,
      ),
    );
  }
}

/// 呼吸浮动：让图标之类的静态元素缓慢上下浮动，给空状态一点生气。
///
/// 系统开启「减弱动态效果」时保持静止。
class BreathingFloat extends StatefulWidget {
  const BreathingFloat({
    super.key,
    required this.child,
    this.amplitude = 3,
  });

  final Widget child;

  /// 上下浮动的最大偏移（逻辑像素）。
  final double amplitude;

  @override
  State<BreathingFloat> createState() => _BreathingFloatState();
}

class _BreathingFloatState extends State<BreathingFloat>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..repeat(reverse: true);

  late final Animation<double> _offset = Tween<double>(
    begin: -1,
    end: 1,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (AppMotion.reduced(context)) {
      return widget.child;
    }
    return AnimatedBuilder(
      animation: _offset,
      builder: (context, child) => Transform.translate(
        offset: Offset(0, _offset.value * widget.amplitude),
        child: child,
      ),
      child: widget.child,
    );
  }
}

/// 数字滚动：从 0 递增到目标值。
///
/// 只用在总结页这类一次性展示的静态数据上；实时刷新的数值不要用它。
class CountUpText extends StatelessWidget {
  const CountUpText({
    super.key,
    required this.value,
    required this.format,
    required this.style,
    this.duration = const Duration(milliseconds: 900),
  });

  final double value;
  final String Function(double value) format;
  final TextStyle style;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final reduced = AppMotion.reduced(context);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: reduced ? value : 0, end: value),
      duration: reduced ? Duration.zero : duration,
      curve: AppMotion.curve,
      builder: (context, current, _) => Text(
        format(current),
        maxLines: 1,
        overflow: TextOverflow.fade,
        softWrap: false,
        style: style,
      ),
    );
  }
}
