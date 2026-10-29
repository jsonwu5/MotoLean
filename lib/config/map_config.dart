/// 腾讯地图 Key 配置。
///
/// Key 不写进仓库，构建时通过 --dart-define 传入：
///
/// ```bash
/// flutter build ios --release \
///   --dart-define=TENCENT_MAP_IOS_KEY=你的iOSKey \
///   --dart-define=TENCENT_MAP_ANDROID_KEY=你的AndroidKey
/// ```
///
/// Key 在 https://lbs.qq.com 控制台创建，需要绑定 Bundle ID
/// （当前为 `com.jsonwoo.motolean`）与 Android 包名。
abstract final class MapConfig {
  static const String iosKey = String.fromEnvironment('TENCENT_MAP_IOS_KEY');

  static const String androidKey = String.fromEnvironment(
    'TENCENT_MAP_ANDROID_KEY',
  );

  /// 是否已经配置了任一平台的 Key。
  static bool get configured => iosKey.isNotEmpty || androidKey.isNotEmpty;
}
