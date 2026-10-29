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
      onPrimary: Colors.white,
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
        foregroundColor: Colors.white,
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
