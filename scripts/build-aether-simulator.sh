#!/bin/bash
# Aether iOS 模拟器构建脚本
# 在 macOS Terminal.app 中运行，绕过 TRAE IDE sandbox 限制

set -e

PROJECT_DIR="/Users/xuchen/Documents/AIBuiler"
PROJECT="$PROJECT_DIR/Aether.xcodeproj"
SCHEME="Aether-iOS"
SIM_NAME="iPhone 17"

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

# 2. 检查/创建模拟器
SIM_ID=$(xcrun simctl list devices available 2>/dev/null | grep "$SIM_NAME" | head -1 | grep -oE '[0-9A-F-]{36}')
if [ -z "$SIM_ID" ]; then
  echo "iPhone 17 模拟器不存在，尝试创建..."
  RUNTIME_ID=$(xcrun simctl list runtimes 2>/dev/null | grep "com.apple.CoreSimulator.SimRuntime.iOS" | head -1 | grep -oE '[0-9A-F-]{36}')
  if [ -z "$RUNTIME_ID" ]; then
    echo "ERROR: 没有可用的 iOS runtime"
    echo "请先运行: xcodebuild -downloadPlatform iOS"
    exit 1
  fi
  xcrun simctl create "$SIM_NAME" "com.apple.CoreSimulator.SimDeviceType.iPhone-17" "$RUNTIME_ID"
  SIM_ID=$(xcrun simctl list devices available 2>/dev/null | grep "$SIM_NAME" | head -1 | grep -oE '[0-9A-F-]{36}')
fi
echo "[OK] 模拟器 ID: $SIM_ID"

# 3. 启动模拟器
echo ""
echo "[3/5] 启动模拟器..."
xcrun simctl boot "$SIM_ID" 2>/dev/null || true
open -a Simulator.app

# 4. Build
echo ""
echo "[4/5] 开始构建 (Build for Testing)..."
xcodebuild build-for-testing \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -destination "platform=iOS Simulator,name=$SIM_NAME,arch=arm64" \
  -configuration Debug \
  -derivedDataPath "$PROJECT_DIR/build" \
  CODE_SIGNING_ALLOWED=NO ARCHS=arm64 2>&1 | tee "$PROJECT_DIR/build/build.log"

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
