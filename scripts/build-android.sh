#!/bin/bash
#
# Aether Android 构建脚本
#
# 支持 Android Debug / Release 构建、单元测试与清理。
#
# 用法:
#   ./scripts/build-android.sh <子命令>
#
# 子命令:
#   build-android          构建 Debug APK (assembleDebug)
#   build-android-release  构建 Release APK (assembleRelease)
#   test-android           运行 Debug 单元测试 (testDebugUnitTest)
#   clean                  清理 Android 构建产物 (gradlew clean)
#
# 环境变量:
#   ANDROID_HOME        覆盖自动检测的 Android SDK 路径
#   ANDROID_SDK_ROOT    备选的 Android SDK 路径环境变量

set -euo pipefail

# 切换到项目根目录（脚本位于 scripts/ 下，向上走一层）
cd "$(dirname "$0")/.."

ANDROID_DIR="android"
GRADLEW="${ANDROID_DIR}/gradlew"

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
# Android SDK 自动检测
# 优先级: ANDROID_HOME > ANDROID_SDK_ROOT > 平台默认路径
# ====================================================================

detect_android_sdk() {
    if [ -n "${ANDROID_HOME:-}" ] && [ -d "$ANDROID_HOME" ]; then
        echo "$ANDROID_HOME"
        return 0
    fi
    if [ -n "${ANDROID_SDK_ROOT:-}" ] && [ -d "$ANDROID_SDK_ROOT" ]; then
        echo "$ANDROID_SDK_ROOT"
        return 0
    fi
    # 平台默认路径
    local home="$HOME"
    local candidate
    case "$(uname -s)" in
        Darwin)
            candidate="${home}/Library/Android/sdk"
            ;;
        Linux)
            candidate="${home}/Android/Sdk"
            ;;
        *)
            # Windows (MSYS/Git Bash) 或未知平台
            candidate="${home}/AppData/Local/Android/Sdk"
            ;;
    esac
    if [ -d "$candidate" ]; then
        echo "$candidate"
        return 0
    fi
    return 1
}

# ====================================================================
# local.properties 自动生成
# 如果 android/local.properties 不存在，写入 sdk.dir
# ====================================================================

ensure_local_properties() {
    local sdk_dir
    if ! sdk_dir=$(detect_android_sdk); then
        log_warn "未检测到 Android SDK，跳过 local.properties 生成"
        log_warn "请设置 ANDROID_HOME 或复制 android/local.properties.example 为 local.properties"
        return 0
    fi
    log_info "检测到 Android SDK: $sdk_dir"
    if [ ! -f "${ANDROID_DIR}/local.properties" ]; then
        log_info "生成 ${ANDROID_DIR}/local.properties"
        # 注意：路径中的反斜杠在 properties 文件中需要转义
        # 使用 printf %s 避免转义被 shell 解析
        local escaped
        escaped=$(printf '%s' "$sdk_dir" | sed 's/\\/\\\\/g')
        printf 'sdk.dir=%s\n' "$escaped" > "${ANDROID_DIR}/local.properties"
        log_success "已生成 ${ANDROID_DIR}/local.properties"
    else
        log_info "已存在 ${ANDROID_DIR}/local.properties，跳过生成"
    fi
    export ANDROID_HOME="$sdk_dir"
    export ANDROID_SDK_ROOT="$sdk_dir"
}

# ====================================================================
# gradlew 校验
# ====================================================================

ensure_gradlew() {
    if [ ! -x "$GRADLEW" ]; then
        if [ ! -f "$GRADLEW" ]; then
            log_error "未找到 gradlew: $GRADLEW"
            log_error "请运行: cd android && gradle wrapper --gradle-version 8.7"
        else
            log_error "gradlew 不可执行: $GRADLEW"
            log_error "请运行: chmod +x $GRADLEW"
        fi
        exit 1
    fi
}

# ====================================================================
# Gradle 任务执行
# ====================================================================

# run_gradle <task...>
run_gradle() {
    (cd "$ANDROID_DIR" && ./gradlew "$@" --no-daemon)
}

# ====================================================================
# 用法
# ====================================================================

print_usage() {
    cat <<EOF
用法: $(basename "$0") <子命令>

子命令:
  build-android          构建 Debug APK (assembleDebug)
  build-android-release  构建 Release APK (assembleRelease)
  test-android           运行 Debug 单元测试 (testDebugUnitTest)
  clean                  清理 Android 构建产物 (gradlew clean)

环境变量:
  ANDROID_HOME        覆盖自动检测的 Android SDK 路径
  ANDROID_SDK_ROOT    备选的 Android SDK 路径环境变量

示例:
  ./scripts/build-android.sh build-android
  ./scripts/build-android.sh build-android-release
  ./scripts/build-android.sh test-android
  ANDROID_HOME=/opt/android-sdk ./scripts/build-android.sh build-android
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

# 校验子命令是否有效
case "$SUBCOMMAND" in
    -h|--help|help)
        print_usage
        exit 0
        ;;
    build-android|build-android-release|test-android|clean)
        ;;
    *)
        log_error "未识别的子命令: $SUBCOMMAND"
        print_usage >&2
        exit 1
        ;;
esac

# clean 不需要 SDK / local.properties
if [ "$SUBCOMMAND" != "clean" ]; then
    ensure_local_properties
fi
ensure_gradlew

case "$SUBCOMMAND" in
    build-android)
        log_info "开始构建 Android Debug APK"
        run_gradle assembleDebug --stacktrace
        log_success "BUILD SUCCEEDED: Android Debug"
        ;;
    build-android-release)
        log_info "开始构建 Android Release APK"
        run_gradle assembleRelease --stacktrace
        log_success "BUILD SUCCEEDED: Android Release"
        ;;
    test-android)
        log_info "开始运行 Android Debug 单元测试"
        run_gradle testDebugUnitTest
        log_success "TEST SUCCEEDED: Android Debug"
        ;;
    clean)
        log_info "清理 Android 构建产物"
        run_gradle clean
        log_success "已清理 Android 构建产物"
        ;;
esac
