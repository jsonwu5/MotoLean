#!/usr/bin/env bash
# 可复现的 iOS 打包脚本。
#
# 任何机器 / 智能体在仓库根目录执行 `tool/build_ios.sh`，只要 .env.local 里的
# Bundle ID 对应的团队与 Key 一致，产出的包就是同一个 App（同样的 Bundle ID、
# 同样的签名团队、同样的腾讯地图 Key），可以直接覆盖安装。
#
# 依赖：Flutter、Xcode、CocoaPods，以及 .env.local（见 .env.example）。
set -euo pipefail

cd "$(dirname "$0")/.."

ENV_FILE=".env.local"
if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

: "${TENCENT_MAP_IOS_KEY:?缺少 TENCENT_MAP_IOS_KEY，请在 .env.local 中配置}"
: "${DEVELOPMENT_TEAM:?缺少 DEVELOPMENT_TEAM，请在 .env.local 中配置}"

# CocoaPods 用 Ruby 处理路径时需要 UTF-8，否则会抛 UnicodeNormalization 异常。
export LANG="${LANG:-en_US.UTF-8}"
export LC_ALL="${LC_ALL:-en_US.UTF-8}"

# 国内网络下 pod install 需要代理；不设置则直连。
if [[ -n "${HTTP_PROXY:-}" ]]; then
  export http_proxy="$HTTP_PROXY"
  export https_proxy="$HTTP_PROXY"
  export all_proxy="$HTTP_PROXY"
fi

# 签名团队写进本地 xcconfig（该文件在 .gitignore 中），避免把 Team ID 提交。
cat > ios/Flutter/Signing.xcconfig <<EOF
// 由 tool/build_ios.sh 生成，请勿手动编辑，也不要提交。
DEVELOPMENT_TEAM = ${DEVELOPMENT_TEAM}
EOF

FLUTTER_BIN="${FLUTTER_BIN:-flutter}"

echo "==> 构建 iOS Release（Bundle ID 由仓库决定，团队 ${DEVELOPMENT_TEAM}）"
"$FLUTTER_BIN" build ios --release \
  --dart-define=TENCENT_MAP_IOS_KEY="${TENCENT_MAP_IOS_KEY}" \
  ${TENCENT_MAP_ANDROID_KEY:+--dart-define=TENCENT_MAP_ANDROID_KEY="${TENCENT_MAP_ANDROID_KEY}"}

if [[ -n "${DEVICE_ID:-}" ]]; then
  echo "==> 安装到设备 ${DEVICE_ID}"
  xcrun devicectl device install app \
    --device "${DEVICE_ID}" build/ios/iphoneos/Runner.app
  if [[ "${LAUNCH:-false}" == "true" ]]; then
    xcrun devicectl device process launch \
      --device "${DEVICE_ID}" com.jsonwoo.motolean || true
  fi
fi

echo "==> 完成"
