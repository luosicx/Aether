#!/bin/bash
# Aether iOS 模拟器构建脚本
# 在 macOS Terminal.app 中运行，绕过 TRAE IDE sandbox 限制

set -e

PROJECT_DIR="/Users/xuchen/Documents/AIBuiler"
PROJECT="$PROJECT_DIR/Aether.xcodeproj"
SCHEME="Aether-iOS"
SIM_NAME="${SIM_NAME:-iPhone 17}"

cd "$PROJECT_DIR"

echo "============================================"
echo "Aether iOS Simulator Build"
echo "============================================"
echo "Project: $PROJECT"
echo "Scheme: $SCHEME"
echo "Simulator: $SIM_NAME"
echo ""

# 1. 检查 xcframework
if [ ! -d "Packages/AetherCore/aether_core.xcframework" ]; then
  echo "ERROR: aether_core.xcframework 不存在"
  echo "请先运行 rust-apple CI job 或本地构建 xcframework"
  exit 1
fi
echo "[OK] xcframework 存在"

# 2. 检查/创建模拟器（委托 ci-setup-simulator.sh，自动选择支持该设备类型的 runtime，含 iPhone Duo 专用 runtime）
SIM_ID=$(xcrun simctl list devices available 2>/dev/null | grep "${SIM_NAME} (" | head -1 | grep -oE '[0-9A-F-]{36}')
if [ -z "$SIM_ID" ]; then
  echo "$SIM_NAME 模拟器不存在，尝试创建..."
  IOS_SIMULATOR_NAME="$SIM_NAME" bash "$PROJECT_DIR/scripts/ci-setup-simulator.sh"
  SIM_ID=$(xcrun simctl list devices available 2>/dev/null | grep "${SIM_NAME} (" | head -1 | grep -oE '[0-9A-F-]{36}')
fi
echo "[OK] 模拟器 ID: $SIM_ID"

# 3. 启动模拟器
echo ""
echo "[3/5] 启动模拟器..."
xcrun simctl boot "$SIM_ID" 2>/dev/null || true
# Xcode 26+ 的模拟器界面换成了 DeviceHub.app（Simulator.app 已不存在），
# 找不到窗口应用时只告警，不能因 set -e 中断构建。
open_simulator_ui() {
  local app
  for app in \
    "$(xcode-select -p)/../Applications/DeviceHub.app" \
    "$(xcode-select -p)/Applications/Simulator.app" \
    "/Applications/Xcode.app/Contents/Applications/DeviceHub.app" \
    "/Applications/Xcode.app/Contents/Developer/Applications/Simulator.app"; do
    if [ -d "$app" ]; then
      open "$app" && return 0
    fi
  done
  echo "[WARN] 未找到模拟器窗口应用（DeviceHub/Simulator），跳过打开窗口"
}
open_simulator_ui

# 4. Build
echo ""
echo "[4/5] 开始构建 (Build)..."
# 不要加 CODE_SIGNING_ALLOWED=NO：模拟器包靠 "Sign to Run Locally" 的 Simulated
# Entitlements 才能拿到 application-identifier/keychain-access-groups，未签名包
# 保存 API Key 会得到 errSecMissingEntitlement (-34018)，表现为「点保存没反应」。
# 用 build 而非 build-for-testing：后者会连带构建 Aether-macOS 测试宿主，
# 在这台机器上因 macOS entitlements 缺开发证书而失败，而本脚本并不跑测试。
xcodebuild build \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -destination "platform=iOS Simulator,name=$SIM_NAME,arch=arm64" \
  -configuration Debug \
  -derivedDataPath "$PROJECT_DIR/build" \
  ARCHS=arm64 2>&1 | tee "$PROJECT_DIR/build/build.log"

BUILD_STATUS=${PIPESTATUS[0]}
if [ $BUILD_STATUS -ne 0 ]; then
  echo ""
  echo "============================================"
  echo "BUILD FAILED (exit $BUILD_STATUS)"
  echo "============================================"
  echo "错误摘要:"
  grep -E "error:|Undefined symbol|linker command failed|cannot find|Could not build" "$PROJECT_DIR/build/build.log" | head -20
  exit $BUILD_STATUS
fi

echo ""
echo "============================================"
echo "BUILD SUCCEEDED"
echo "============================================"

# 5. 安装到模拟器
echo ""
echo "[5/5] 安装应用到模拟器..."
APP_PATH=$(find "$PROJECT_DIR/build/Build/Products" -name "Aether.app" -type d 2>/dev/null | head -1)
if [ -z "$APP_PATH" ]; then
  echo "WARNING: 未找到 Aether.app，跳过安装"
  exit 0
fi
echo "App path: $APP_PATH"
xcrun simctl install "$SIM_ID" "$APP_PATH"
echo "[OK] 应用已安装到 $SIM_NAME"

# 启动应用
echo ""
echo "启动 Aether..."
BUNDLE_ID=$(defaults read "$APP_PATH/Info.plist" CFBundleIdentifier 2>/dev/null || echo "com.luosicx.Aether")
xcrun simctl launch "$SIM_ID" "$BUNDLE_ID" 2>/dev/null || \
  echo "请在模拟器中手动启动 Aether"

echo ""
echo "============================================"
echo "ALL DONE - Aether 已构建并安装"
echo "============================================"
