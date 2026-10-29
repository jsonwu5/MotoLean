import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

/// 配色取自春风 450SR-S「星耀白」实车：
///
/// - 车漆白：`#F2F5F6` 页面底、纯白卡片
/// - 品牌青蓝（SR-S 标识）：`#00EEFC` 原色过亮，白底上拆成两种用途
///   - [accent] 用于填充块与图形（上面压深色字）
///   - [accentInk] 用于白底上的文字、图标与细弧线（对比度 5.9:1）
/// - 轮毂蓝：`#0F7CB8`，作为左倾 / 次要强调色
/// - 碳纤黑：`#0F171C`，正文色
abstract final class AppColors {
  // 车漆白：页面底色与卡片
  static const background = Color(0xFFF2F5F6);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceHigh = Color(0xFFEDF2F4);
  static const surfaceHighest = Color(0xFFDEE6EA);

  // 品牌青蓝
  static const accent = Color(0xFF00A5B8);
  static const accentInk = Color(0xFF006E7F);
  static const accentSoft = Color(0xFFD9F5F8);

  // 轮毂蓝
  static const blue = Color(0xFF0F7CB8);
  static const blueSoft = Color(0xFFDCEBF7);

  static const amber = Color(0xFF9A5A00);
  static const orange = Color(0xFFD9561F);
  static const danger = Color(0xFFD6342C);

  // 压在高亮填充上的深色字
  static const onAccent = Color(0xFF05252B);

  static const textPrimary = Color(0xFF0F171C);
  static const textSecondary = Color(0xFF55636D);
  static const textTertiary = Color(0xFF68757F);
  static const divider = Color(0xFFE1E8EB);

  /// 卡片顶部的柔和青雾，呼应车漆在自然光下的冷调高光。
  static const cyanWash = Color(0xFFEAF7F9);
}

/// 记录中仪表盘的深色「夜间模式」色板。
///
/// 只在骑行进行中的界面使用（记录页仪表盘），碳黑底 + 青蓝读数，
/// 夜间骑行不刺眼，也与全屏轨迹回放的黑色沉浸保持一致。
abstract final class AppDash {
  static const background = Color(0xFF0A0F12);
  static const surface = Color(0xFF131B20);
  static const surfaceHigh = Color(0xFF1D282F);
  static const surfaceHighest = Color(0xFF2A3740);
  static const divider = Color(0xFF26323A);

  static const textPrimary = Color(0xFFEDF4F6);
  static const textSecondary = Color(0xFFA3B4BD);
  static const textTertiary = Color(0xFF71828C);

  /// 深色底上的语义色：比浅色版亮一档，保证对比度。
  static const accent = Color(0xFF2FD8E8);
  static const blue = Color(0xFF4FA8E0);
  static const amber = Color(0xFFE8A94B);
  static const danger = Color(0xFFF06A5E);

  /// 压在亮色 danger 按钮上的深色字。
  static const onDanger = Color(0xFF2A0D08);
}

/// 数字与英文展示字体（Rajdhani，OFL 许可）：方正的仪表腔调。
/// 中文字形会自动回退到系统字体，混排安全。
const String kDisplayFont = 'Rajdhani';

/// 大尺寸读数（时速、秒表、倾角、成绩）的统一样式。
///
/// 仪表惯例的轻微斜体由引擎合成；[slanted] 关闭时用于小字场景。
TextStyle displayNumber({
  required double fontSize,
  Color color = AppColors.textPrimary,
  FontWeight fontWeight = FontWeight.w700,
  double letterSpacing = 0,
  double height = 1,
  bool slanted = true,
}) => TextStyle(
  fontFamily: kDisplayFont,
  fontSize: fontSize,
  height: height,
  fontWeight: fontWeight,
  letterSpacing: letterSpacing,
  fontStyle: slanted ? FontStyle.italic : FontStyle.normal,
  color: color,
  fontFeatures: tabularFigures,
);

/// 加速域的卡片渐变：轮毂蓝的冷调高光，与骑行驶的青色区分。
const LinearGradient accelCardGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFFDCEBF7), Color(0xFFF3F8FB)],
);

const List<FontFeature> tabularFigures = [FontFeature.tabularFigures()];

/// 全局动效规格：统一时长与曲线，并尊重系统「减弱动态效果」。
abstract final class AppMotion {
  /// 微交互（按压、开关）。
  static const fast = Duration(milliseconds: 150);

  /// 卡片与状态切换。
  static const med = Duration(milliseconds: 280);

  /// 入场编排。
  static const slow = Duration(milliseconds: 500);

  /// 入场曲线。
  static const curve = Curves.easeOutCubic;

  /// 离场曲线。
  static const curveExit = Curves.easeInCubic;

  /// 系统是否开启了「减弱动态效果」。
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;
}

ThemeData buildAppTheme() {
  final base = ThemeData(
    brightness: Brightness.light,
    useMaterial3: true,
    colorScheme: const ColorScheme.light(
      primary: AppColors.accent,
      onPrimary: AppColors.onAccent,
      secondary: AppColors.blue,
      onSecondary: Colors.white,
      surface: AppColors.surface,
      onSurface: AppColors.textPrimary,
      error: AppColors.danger,
      onError: Colors.white,
    ),
    scaffoldBackgroundColor: AppColors.background,
  );

  return base.copyWith(
    textTheme: base.textTheme
        .apply(
          bodyColor: AppColors.textPrimary,
          displayColor: AppColors.textPrimary,
        )
        .copyWith(
          displayLarge: const TextStyle(
            fontSize: 76,
            height: 0.95,
            fontWeight: FontWeight.w800,
            letterSpacing: -3,
            fontFeatures: tabularFigures,
          ),
          displayMedium: const TextStyle(
            fontSize: 54,
            height: 1,
            fontWeight: FontWeight.w800,
            letterSpacing: -2,
            fontFeatures: tabularFigures,
          ),
          headlineMedium: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
          titleMedium: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
          bodyMedium: const TextStyle(
            fontSize: 14,
            height: 1.45,
            color: AppColors.textSecondary,
          ),
          labelSmall: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
            color: AppColors.textTertiary,
          ),
        ),
    iconTheme: const IconThemeData(color: AppColors.textPrimary),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      ),
      iconTheme: IconThemeData(color: AppColors.textPrimary),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.accent,
        // 青蓝填充上压深色字（5.4:1），白字只有约 3:1 不达标。
        foregroundColor: AppColors.onAccent,
        minimumSize: const Size.fromHeight(56),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.2,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.textPrimary,
        minimumSize: const Size.fromHeight(52),
        side: const BorderSide(color: AppColors.divider),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.accentInk,
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.textPrimary,
      contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titleTextStyle: const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      ),
      contentTextStyle: const TextStyle(
        fontSize: 14,
        height: 1.5,
        color: AppColors.textSecondary,
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: AppColors.surface,
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.divider,
      thickness: 1,
      space: 1,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.accent,
      linearTrackColor: AppColors.surfaceHighest,
      circularTrackColor: AppColors.surfaceHighest,
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: AppColors.accent,
      inactiveTrackColor: AppColors.surfaceHighest,
      thumbColor: AppColors.accentInk,
      overlayColor: Color(0x1A00A5B8),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? AppColors.surface
            : AppColors.surfaceHighest,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? AppColors.accent
            : AppColors.surfaceHighest,
      ),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: _FadeUpPageTransitionsBuilder(),
        TargetPlatform.linux: _FadeUpPageTransitionsBuilder(),
        TargetPlatform.windows: _FadeUpPageTransitionsBuilder(),
        TargetPlatform.fuchsia: _FadeUpPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
      },
    ),
  );
}

BoxDecoration cardDecoration({
  Color color = AppColors.surface,
  double radius = 22,
  Gradient? gradient,
}) => BoxDecoration(
  color: gradient == null ? color : null,
  gradient: gradient,
  borderRadius: BorderRadius.circular(radius),
  border: Border.all(color: AppColors.divider),
);

/// 克制的淡出 + 轻微上滑页面转场（iOS/macOS 保持原生侧滑返回手势）。
class _FadeUpPageTransitionsBuilder extends PageTransitionsBuilder {
  const _FadeUpPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: AppMotion.curve,
      reverseCurve: AppMotion.curveExit,
    );
    final fade = FadeTransition(opacity: curved, child: child);
    if (AppMotion.reduced(context)) {
      return fade;
    }
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, 0.035),
        end: Offset.zero,
      ).animate(curved),
      child: fade,
    );
  }
}
