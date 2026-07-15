#!/bin/bash
#
# Aether macOS .dmg 打包脚本
#
# 支持三种模式：
#   --unsigned  （默认）无签名打包，输出 Aether-{version}-unsigned.dmg
#   --signed    Developer ID 签名打包，输出 Aether-{version}.dmg
#   --notarize  配合 --signed 使用，提交 Apple 公证并装订
#
# 用法：
#   ./scripts/build-dmg.sh [--unsigned|--signed [--notarize]] [--app-version <ver>] [--help]
#

set -euo pipefail

# 切换到项目根目录（脚本位于 scripts/ 下，向上走一层）
cd "$(dirname "$0")/.."

# 项目固定配置
PROJECT="Aether.xcodeproj"
SCHEME="Aether-macOS"
INFO_PLIST="Aether/Resources/Info.plist"
APP_NAME="Aether"

# 模式开关（默认无签名模式）
MODE="unsigned"
NOTARIZE=false
# 版本号覆盖（空表示从 Info.plist 读取）
APP_VERSION_OVERRIDE=""

# ====================================================================
# 公共函数
# ====================================================================

# 打印蓝色 info 日志到 stderr
log_info() {
    printf '\033[0;34m[INFO]\033[0m %s\n' "$*" >&2
}

# 打印红色 error 日志到 stderr
log_error() {
    printf '\033[0;31m[ERROR]\033[0m %s\n' "$*" >&2
}

# 临时 staging 目录，cleanup 时清理
DMG_STAGING="build/dmg-staging"

# trap EXIT 时清理临时 staging 目录
cleanup() {
    if [ -d "$DMG_STAGING" ]; then
        rm -rf "$DMG_STAGING"
    fi
}
trap cleanup EXIT

# 打印用法
print_usage() {
    cat <<EOF
用法: $(basename "$0") [选项]

选项:
  --unsigned            无签名模式（默认），输出 Aether-{version}-unsigned.dmg
  --signed              Developer ID 签名模式，输出 Aether-{version}.dmg
  --notarize            配合 --signed 使用，提交 Apple 公证并装订
  --app-version <ver>   覆盖版本号（默认从 Info.plist 读取 CFBundleShortVersionString）
  --help                打印此帮助信息

环境变量（仅 --signed / --notarize 时需要）:
  DEVELOPER_ID_APPLICATION  Developer ID Application 签名身份（--signed 必填）
  TEAM_ID                   Apple 开发者团队 ID（--signed 可选；--notarize 必填）
  APPLE_ID                  Apple ID 账号（仅 --notarize 必填）
  APP_SPECIFIC_PASSWORD     App 专用密码（仅 --notarize 必填）

示例:
  # 无签名打包
  ./scripts/build-dmg.sh

  # 指定版本号的无签名打包
  ./scripts/build-dmg.sh --unsigned --app-version 1.2.0

  # Developer ID 签名打包
  DEVELOPER_ID_APPLICATION="Developer ID Application: ..." \\
  TEAM_ID=XXXXXXXXXX \\
  ./scripts/build-dmg.sh --signed

  # 签名 + 公证
  DEVELOPER_ID_APPLICATION="Developer ID Application: ..." \\
  TEAM_ID=XXXXXXXXXX APPLE_ID=you@example.com \\
  APP_SPECIFIC_PASSWORD=xxxx-xxxx-xxxx-xxxx \\
  ./scripts/build-dmg.sh --signed --notarize
EOF
}

# ====================================================================
# 参数解析
# ====================================================================

while [ $# -gt 0 ]; do
    case "$1" in
        --unsigned)
            MODE="unsigned"
            shift
            ;;
        --signed)
            MODE="signed"
            shift
            ;;
        --notarize)
            NOTARIZE=true
            shift
            ;;
        --app-version)
            if [ $# -lt 2 ]; then
                log_error "--app-version 需要一个参数"
                exit 1
            fi
            APP_VERSION_OVERRIDE="$2"
            shift 2
            ;;
        --help)
            print_usage
            exit 0
            ;;
        *)
            log_error "未知参数: $1"
            print_usage >&2
            exit 1
            ;;
    esac
done

# --notarize 必须配合 --signed 使用
if [ "$NOTARIZE" = "true" ] && [ "$MODE" != "signed" ]; then
    log_error "--notarize 必须配合 --signed 使用"
    exit 1
fi

# ====================================================================
# 版本号读取
# ====================================================================

if [ -n "$APP_VERSION_OVERRIDE" ]; then
    APP_VERSION="$APP_VERSION_OVERRIDE"
    log_info "使用覆盖版本号: $APP_VERSION"
else
    if [ ! -f "$INFO_PLIST" ]; then
        log_error "未找到 Info.plist: $INFO_PLIST"
        exit 1
    fi
    APP_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST")
    log_info "从 Info.plist 读取版本号: $APP_VERSION"
fi

# ====================================================================
# 构建产物路径变量（后续根据模式填充）
# ====================================================================
APP_PATH=""

# ====================================================================
# --unsigned 模式：xcodebuild build
# ====================================================================

if [ "$MODE" = "unsigned" ]; then
    log_info "进入无签名构建模式"
    log_info "执行 xcodebuild build ..."
    xcodebuild build \
        -project "$PROJECT" \
        -scheme "$SCHEME" \
        -destination 'platform=macOS' \
        -configuration Release \
        -derivedDataPath build/DerivedData \
        CODE_SIGNING_ALLOWED=NO

    APP_PATH="build/DerivedData/Build/Products/Release/${APP_NAME}.app"
    if [ ! -d "$APP_PATH" ]; then
        log_error "未找到构建产物: $APP_PATH"
        exit 1
    fi
    log_info "构建产物: $APP_PATH"

# ====================================================================
# --signed 模式：xcodebuild archive + exportArchive
# ====================================================================
elif [ "$MODE" = "signed" ]; then
    log_info "进入 Developer ID 签名构建模式"

    # 校验 DEVELOPER_ID_APPLICATION 非空
    if [ -z "${DEVELOPER_ID_APPLICATION:-}" ]; then
        log_error "环境变量 DEVELOPER_ID_APPLICATION 未设置（--signed 模式必填）"
        exit 1
    fi

    log_info "执行 xcodebuild archive ..."
    xcodebuild archive \
        -project "$PROJECT" \
        -scheme "$SCHEME" \
        -destination 'generic/platform=macOS' \
        -archivePath build/Aether.xcarchive \
        CODE_SIGN_IDENTITY="$DEVELOPER_ID_APPLICATION"

    # 生成 ExportOptions.plist
    log_info "生成 build/ExportOptions.plist"
    EXPORT_PLIST="build/ExportOptions.plist"
    mkdir -p build
    if [ -n "${TEAM_ID:-}" ]; then
        cat > "$EXPORT_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <method>developer-id</method>
    <signingStyle>manual</signingStyle>
    <teamID>${TEAM_ID}</teamID>
</dict>
</plist>
EOF
    else
        cat > "$EXPORT_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <method>developer-id</method>
    <signingStyle>manual</signingStyle>
</dict>
</plist>
EOF
    fi

    log_info "执行 xcodebuild -exportArchive ..."
    xcodebuild -exportArchive \
        -archivePath build/Aether.xcarchive \
        -exportOptionsPlist "$EXPORT_PLIST" \
        -exportPath build/export

    APP_PATH="build/export/${APP_NAME}.app"
    if [ ! -d "$APP_PATH" ]; then
        log_error "未找到导出产物: $APP_PATH"
        exit 1
    fi
    log_info "导出产物: $APP_PATH"

    # ====================================================================
    # --notarize 流程（仅 --signed --notarize 时执行）
    # ====================================================================
    if [ "$NOTARIZE" = "true" ]; then
        log_info "进入 Apple 公证流程"

        # 校验公证所需环境变量
        if [ -z "${APP_SPECIFIC_PASSWORD:-}" ]; then
            log_error "环境变量 APP_SPECIFIC_PASSWORD 未设置（--notarize 必填）"
            exit 1
        fi
        if [ -z "${APPLE_ID:-}" ]; then
            log_error "环境变量 APPLE_ID 未设置（--notarize 必填）"
            exit 1
        fi
        if [ -z "${TEAM_ID:-}" ]; then
            log_error "环境变量 TEAM_ID 未设置（--notarize 必填）"
            exit 1
        fi

        # 强化运行时签名
        log_info "强化运行时签名 (codesign --options runtime) ..."
        codesign --deep --force --options runtime \
            --sign "$DEVELOPER_ID_APPLICATION" "$APP_PATH"

        # 压缩用于公证
        log_info "压缩 $APP_PATH -> build/Aether.zip"
        ditto -c -k --keepParent "$APP_PATH" build/Aether.zip

        # 提交公证并等待结果
        log_info "提交 Apple 公证 (notarytool submit --wait) ..."
        xcrun notarytool submit build/Aether.zip \
            --apple-id "$APPLE_ID" \
            --password "$APP_SPECIFIC_PASSWORD" \
            --team-id "$TEAM_ID" \
            --wait

        # 装订公证票据
        log_info "装订公证票据 (stapler staple) ..."
        xcrun stapler staple "$APP_PATH"

        # 验证装订
        log_info "验证装订 (stapler validate) ..."
        xcrun stapler validate "$APP_PATH"
    fi
fi

# ====================================================================
# .dmg 生成公共逻辑
# ====================================================================

log_info "开始生成 .dmg"

# 1. 创建 staging 目录
mkdir -p "$DMG_STAGING"

# 2. 拷贝 .app 到 staging
log_info "拷贝 $APP_PATH -> $DMG_STAGING/${APP_NAME}.app"
cp -R "$APP_PATH" "$DMG_STAGING/${APP_NAME}.app"

# 3. 创建 /Applications 软链接
ln -s /Applications "$DMG_STAGING/Applications"

# 4. 创建输出目录
mkdir -p build/dmg

# 5. 确定 .dmg 文件名
if [ "$MODE" = "signed" ]; then
    DMG_FILENAME="${APP_NAME}-${APP_VERSION}.dmg"
else
    DMG_FILENAME="${APP_NAME}-${APP_VERSION}-unsigned.dmg"
fi
DMG_OUTPUT_PATH="build/dmg/${DMG_FILENAME}"

# 6. 执行 hdiutil 创建 .dmg
log_info "执行 hdiutil create -> $DMG_OUTPUT_PATH"
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$DMG_STAGING" \
    -fs HFS+ \
    -format UDZO \
    "$DMG_OUTPUT_PATH"

# 7. 打印最终 .dmg 绝对路径
FINAL_DMG_PATH="$(cd build/dmg && pwd)/${DMG_FILENAME}"
log_info "DMG 生成完成: $FINAL_DMG_PATH"

# 同时输出到 stdout，便于脚本化消费
echo "$FINAL_DMG_PATH"
