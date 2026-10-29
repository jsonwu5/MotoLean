import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_tencent_map/flutter_tencent_map.dart';

import 'app.dart';
import 'config/map_config.dart';
import 'services/ride_store.dart';
import 'services/settings_service.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
      systemNavigationBarColor: AppColors.background,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );
  await _initTencentMap();

  final store = RideStore();
  final settings = SettingsService();
  try {
    // 设置读取失败不应该阻止启动，SettingsService 内部已做兜底。
    await settings.load();
    await store.init();
    runApp(MotoLeanApp(store: store, settings: settings));
  } catch (error) {
    runApp(_StartupFailureApp(message: '$error'));
  }
}

/// 腾讯地图 SDK 要求先声明隐私协议、再启动。
/// 未配置 Key 时整段跳过，地图组件会显示未启用的占位卡。
Future<void> _initTencentMap() async {
  if (!MapConfig.configured) {
    return;
  }
  try {
    await TencentMapInitializer.setAgreePrivacy(true);
    await TencentMapInitializer.start();
  } catch (_) {
    // 地图初始化失败不应阻塞记录功能。
  }
}

class _StartupFailureApp extends StatelessWidget {
  const _StartupFailureApp({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '摩倾 MotoLean',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.storage_rounded,
                    color: AppColors.danger,
                    size: 40,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '无法打开本地数据库',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.6,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '请检查设备存储空间后重新打开应用。',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
