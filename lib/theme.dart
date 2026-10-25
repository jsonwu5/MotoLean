import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

abstract final class AppColors {
  static const background = Color(0xFF0A0B0D);
  static const surface = Color(0xFF15171C);
  static const surfaceHigh = Color(0xFF1D2027);
  static const surfaceHighest = Color(0xFF262A33);
  static const accent = Color(0xFFC8FF3D);
  static const accentDark = Color(0xFF2A3510);
  static const cyan = Color(0xFF5BE7FF);
  static const amber = Color(0xFFFFB020);
  static const orange = Color(0xFFFF7A2F);
  static const danger = Color(0xFFFF4D4F);
  static const textPrimary = Color(0xFFF4F6F8);
  static const textSecondary = Color(0xFF8E96A3);
  static const textTertiary = Color(0xFF5C636E);
  static const divider = Color(0xFF242830);
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
    brightness: Brightness.dark,
    useMaterial3: true,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.accent,
      onPrimary: Color(0xFF111400),
      secondary: AppColors.cyan,
      onSecondary: Color(0xFF001A1F),
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
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
            color: AppColors.textTertiary,
          ),
        ),
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
        foregroundColor: const Color(0xFF101400),
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
        foregroundColor: AppColors.accent,
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.surfaceHighest,
      contentTextStyle: const TextStyle(
        color: AppColors.textPrimary,
        fontSize: 14,
      ),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surfaceHigh,
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
      backgroundColor: AppColors.surfaceHigh,
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: AppColors.surfaceHigh,
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.divider,
      thickness: 1,
      space: 1,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.accent,
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
  border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
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
