#!/bin/bash
#
# Aether Apple 平台构建脚本
#
# 支持 iOS / macOS / watchOS / Widget Extension 的构建、测试与运行。
#
# 用法:
#   ./scripts/build.sh <子命令>
#
# 子命令:
#   build-ios     构建 iOS 模拟器版本 (Aether-iOS scheme)
#   build-macos   构建 macOS 版本 (Aether-macOS scheme)
#   build-watch   构建 watchOS 模拟器版本 (AetherWatch scheme)
#   build-widget  构建 Widget Extension (AetherWidgets scheme, iOS 模拟器)
#   test-ios      运行 iOS 单元 + UI 测试 (AetherTests + AetherUITests)
#   test-macos    运行 macOS 单元测试 (AetherTests)
#   test-unit     仅运行 iOS 单元测试 (AetherTests)
#   clean         清理 build/ 目录
#   run-ios       构建并启动 iOS 模拟器 (build + boot + install + launch)
#
# 环境变量:
#   SCHEME        覆盖默认 scheme
#   DESTINATION   覆盖默认 destination
#   CONFIG        覆盖 configuration (Debug/Release, 默认 Debug)
#   DEVELOPER_DIR 覆盖自动检测的 Xcode 开发者目录
#   STRICT_CONCURRENCY  覆盖 SWIFT_STRICT_CONCURRENCY (complete/minimal, 默认 complete)

set -euo pipefail

# 切换到项目根目录（脚本位于 scripts/ 下，向上走一层）
cd "$(dirname "$0")/.."

PROJECT="Aether.xcodeproj"
DERIVED_DATA_PATH="build/DerivedData"

# Task 8: 默认启用 SWIFT_STRICT_CONCURRENCY=complete，与 CI 保持一致。
# 通过 STRICT_CONCURRENCY 环境变量可覆盖（如 STRICT_CONCURRENCY=minimal 用于本地调试）。
STRICT_CONCURRENCY="${STRICT_CONCURRENCY:-complete}"

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# ====================================================================
# 日志函数
# ====================================================================

log_info() {
    printf "${GREEN}[INFO]${NC} %s\n" "$*" >&2
}

log_success() {
    printf "${GREEN}[OK]${NC} %s\n" "$*" >&2
}

log_warn() {
    printf "${YELLOW}[WARN]${NC} %s\n" "$*" >&2
}

log_error() {
    printf "${RED}[ERROR]${NC} %s\n" "$*" >&2
}

# ====================================================================
# DEVELOPER_DIR 自动检测
# 优先使用 /Applications/Xcode.app，fallback 到 Xcode-beta.app
# ====================================================================
detect_developer_dir() {
    if [ -n "${DEVELOPER_DIR:-}" ]; then
        log_info "使用环境变量 DEVELOPER_DIR: $DEVELOPER_DIR"
        return 0
    fi
    if [ -d "/Applications/Xcode.app/Contents/Developer" ]; then
        export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
        log_info "检测到 Xcode: $DEVELOPER_DIR"
    elif [ -d "/Applications/Xcode-beta.app/Contents/Developer" ]; then
        export DEVELOPER_DIR="/Applications/Xcode-beta.app/Contents/Developer"
        log_info "检测到 Xcode-beta: $DEVELOPER_DIR"
    else
        log_error "未找到 Xcode，请安装 Xcode 或设置 DEVELOPER_DIR 环境变量"
        log_error "已尝试: /Applications/Xcode.app 与 /Applications/Xcode-beta.app"
        exit 1
    fi
}

# ====================================================================
# 模拟器检测
# ====================================================================

# 检测可用的 iPhone 模拟器（回退链：iPhone 17 → iPhone 16 Pro → iPhone 16 → iPhone 15）
# 使用 "${name} (" 精确匹配，避免 "iPhone 16" 误匹配 "iPhone 16 Pro"
detect_ios_simulator() {
    local candidates=("iPhone 17" "iPhone 16 Pro" "iPhone 16" "iPhone 15")
    local available
    available=$(xcrun simctl list devices available 2>/dev/null || true)
    for name in "${candidates[@]}"; do
        if echo "$available" | grep -q "${name} ("; then
            echo "$name"
            return 0
        fi
    done
    log_error "未找到可用的 iPhone 模拟器（已尝试: ${candidates[*]}）"
    log_error "可运行 scripts/ci-setup-simulator.sh 创建模拟器"
    exit 1
}

# 检测可用的 Apple Watch 模拟器（回退链）
detect_watch_simulator() {
    local candidates=("Apple Watch Series 11" "Apple Watch Series 10" "Apple Watch Series 9" "Apple Watch Series 8")
    local available
    available=$(xcrun simctl list devices available 2>/dev/null || true)
    for name in "${candidates[@]}"; do
        if echo "$available" | grep -q "${name} ("; then
            echo "$name"
            return 0
        fi
    done
    log_error "未找到可用的 Apple Watch 模拟器（已尝试: ${candidates[*]}）"
    exit 1
}

# ====================================================================
# 构建 / 测试
# ====================================================================

# run_build <scheme> <destination>
# 环境变量 SCHEME / DESTINATION 可覆盖默认值
run_build() {
    local scheme="$1"
    local destination="$2"
    scheme="${SCHEME:-$scheme}"
    destination="${DESTINATION:-$destination}"

    log_info "开始构建: scheme=$scheme, config=$CONFIG"
    log_info "destination=$destination"
    xcodebuild build \
        -project "$PROJECT" \
        -scheme "$scheme" \
        -destination "$destination" \
        -configuration "$CONFIG" \
        -derivedDataPath "$DERIVED_DATA_PATH" \
        CODE_SIGNING_ALLOWED=NO \
        SWIFT_STRICT_CONCURRENCY="$STRICT_CONCURRENCY"
    log_success "BUILD SUCCEEDED: $scheme"
}

# run_test <scheme> <destination> [extra xcodebuild args...]
# 环境变量 SCHEME / DESTINATION 可覆盖默认值
run_test() {
    local scheme="$1"
    local destination="$2"
    shift 2
    scheme="${SCHEME:-$scheme}"
    destination="${DESTINATION:-$destination}"

    log_info "开始测试: scheme=$scheme, config=$CONFIG"
    log_info "destination=$destination"
    if [ $# -gt 0 ]; then
        log_info "测试目标: $*"
    fi
    xcodebuild test \
        -project "$PROJECT" \
        -scheme "$scheme" \
        -destination "$destination" \
        -configuration "$CONFIG" \
        -derivedDataPath "$DERIVED_DATA_PATH" \
        CODE_SIGNING_ALLOWED=NO \
        SWIFT_STRICT_CONCURRENCY="$STRICT_CONCURRENCY" \
        "$@"
    log_success "TEST SUCCEEDED: $scheme"
}

# ====================================================================
# run-ios: 构建 + 启动模拟器 + 安装 + 启动 App
# ====================================================================
run_ios() {
    local sim_name
    sim_name=$(detect_ios_simulator)
    local destination="platform=iOS Simulator,name=${sim_name}"

    # 1. 构建
    run_build "Aether-iOS" "$destination"

    # 2. 获取模拟器 UDID
    local udid
    udid=$(xcrun simctl list devices available -j | python3 -c "
import json, sys
data = json.load(sys.stdin)
target = '${sim_name}'
for runtime, devices in data['devices'].items():
    for d in devices:
        if d.get('name') == target and d.get('isAvailable'):
            print(d['udid'])
            sys.exit(0)
")
    if [ -z "$udid" ]; then
        log_error "无法获取模拟器 UDID: $sim_name"
        exit 1
    fi

    # 3. 启动模拟器
    log_info "启动模拟器: $sim_name ($udid)"
    xcrun simctl boot "$udid" 2>/dev/null || log_warn "模拟器可能已启动"
    open -a Simulator 2>/dev/null || true

    # 4. 定位 .app 产物
    local config_dir
    if [ "$CONFIG" = "Release" ]; then
        config_dir="Release-iphonesimulator"
    else
        config_dir="Debug-iphonesimulator"
    fi
    local app_path="${DERIVED_DATA_PATH}/Build/Products/${config_dir}/Aether.app"
    if [ ! -d "$app_path" ]; then
        log_error "未找到构建产物: $app_path"
        exit 1
    fi

    # 5. 安装 App
    log_info "安装 App: $app_path"
    xcrun simctl install "$udid" "$app_path"

    # 6. 启动 App
    log_info "启动 App: com.aether.app.ios"
    xcrun simctl launch "$udid" "com.aether.app.ios"
    log_success "App 已启动: Aether (iOS Simulator)"
}

# ====================================================================
# 用法
# ====================================================================
print_usage() {
    cat <<EOF
用法: $(basename "$0") <子命令>

子命令:
  build-ios     构建 iOS 模拟器版本 (Aether-iOS scheme)
  build-macos   构建 macOS 版本 (Aether-macOS scheme)
  build-watch   构建 watchOS 模拟器版本 (AetherWatch scheme)
  build-widget  构建 Widget Extension (AetherWidgets scheme, iOS 模拟器)
  test-ios      运行 iOS 单元 + UI 测试 (AetherTests + AetherUITests)
  test-macos    运行 macOS 单元测试 (AetherTests)
  test-unit     仅运行 iOS 单元测试 (AetherTests)
  clean         清理 build/ 目录
  run-ios       构建并启动 iOS 模拟器 (build + boot + install + launch)

环境变量:
  SCHEME        覆盖默认 scheme
  DESTINATION   覆盖默认 destination
  CONFIG        覆盖 configuration (Debug/Release, 默认 Debug)
  DEVELOPER_DIR 覆盖自动检测的 Xcode 开发者目录
  STRICT_CONCURRENCY  覆盖 SWIFT_STRICT_CONCURRENCY (complete/minimal, 默认 complete)

示例:
  ./scripts/build.sh build-ios
  ./scripts/build.sh build-macos
  CONFIG=Release ./scripts/build.sh build-ios
  STRICT_CONCURRENCY=minimal ./scripts/build.sh build-ios
  DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer ./scripts/build.sh build-ios
EOF
}

# ====================================================================
# 主逻辑
# ====================================================================

if [ $# -lt 1 ]; then
    log_error "缺少子命令"
    print_usage >&2
    exit 1
fi

SUBCOMMAND="$1"
shift

# 默认 configuration (Debug/Release)
CONFIG="${CONFIG:-Debug}"

# 先处理无需 Xcode 的命令（help / clean）
case "$SUBCOMMAND" in
    -h|--help|help)
        print_usage
        exit 0
        ;;
    clean)
        log_info "清理 build/ 目录"
        rm -rf build/
        log_success "已清理 build/"
        exit 0
        ;;
esac

# 校验子命令是否有效
case "$SUBCOMMAND" in
    build-ios|build-macos|build-watch|build-widget|test-ios|test-macos|test-unit|run-ios)
        ;;
    *)
        log_error "未识别的子命令: $SUBCOMMAND"
        print_usage >&2
        exit 1
        ;;
esac

# 构建/测试/运行命令需要 Xcode，自动检测 DEVELOPER_DIR
detect_developer_dir

case "$SUBCOMMAND" in
    build-ios)
        sim_name=$(detect_ios_simulator)
        destination="platform=iOS Simulator,name=${sim_name}"
        run_build "Aether-iOS" "$destination"
        ;;
    build-macos)
        destination="platform=macOS"
        run_build "Aether-macOS" "$destination"
        ;;
    build-watch)
        if [ -n "$DESTINATION" ]; then
            destination="$DESTINATION"
        else
            watch_name=$(detect_watch_simulator)
            destination="platform=watchOS Simulator,name=${watch_name}"
        fi
        run_build "AetherWatch" "$destination"
        ;;
    build-widget)
        if [ -n "$DESTINATION" ]; then
            destination="$DESTINATION"
        else
            sim_name=$(detect_ios_simulator)
            destination="platform=iOS Simulator,name=${sim_name}"
        fi
        run_build "AetherWidgets" "$destination"
        ;;
    test-ios)
        sim_name=$(detect_ios_simulator)
        destination="platform=iOS Simulator,name=${sim_name}"
        # Aether-iOS scheme 默认包含 AetherTests + AetherUITests
        run_test "Aether-iOS" "$destination"
        ;;
    test-macos)
        destination="platform=macOS"
        run_test "Aether-macOS" "$destination" -only-testing:AetherTests
        ;;
    test-unit)
        sim_name=$(detect_ios_simulator)
        destination="platform=iOS Simulator,name=${sim_name}"
        run_test "Aether-iOS" "$destination" -only-testing:AetherTests
        ;;
    run-ios)
        run_ios
        ;;
esac
