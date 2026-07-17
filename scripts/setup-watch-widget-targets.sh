#!/usr/bin/env bash
set -euo pipefail
# Watch/Widget target 完整性验证脚本（幂等）
#
# 用途：在 CI 或本地环境中验证 AetherWatch / AetherWidgets 两个 target 的完整性，
#   包括目录存在、核心源文件齐全、Xcode project 中 scheme 已注册、
#   entitlements 包含 App Group (group.com.aether.app) 配置。
#
# 幂等：本脚本只读验证，不会创建、修改或删除任何 target、源文件或配置，
#   可重复运行，结果一致。
#
# 退出码：全部检查通过 exit 0；任一检查失败 exit 1。

FAIL=0

# 项目根目录（脚本位于 scripts/ 下，根目录为其上一级）
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

WATCH_DIR="AetherWatch"
WIDGET_DIR="AetherWidgets"
PROJECT_FILE="Aether.xcodeproj"
APP_GROUP="group.com.aether.app"

# 期望存在的核心源文件（按文件名，在对应 target 目录下递归查找）
WATCH_CORE_FILES=(
  "WatchApp.swift"
  "WatchHealthInsightView.swift"
  "WatchQuickChatView.swift"
  "AetherWatch.entitlements"
)

WIDGET_CORE_FILES=(
  "AetherWidgetBundle.swift"
  "HealthInsightWidget.swift"
  "QuickChatWidget.swift"
  "RecentConversationsWidget.swift"
  "AetherWidgets.entitlements"
)

echo "=== Watch/Widget target 完整性验证 ==="
echo ""

# 在指定目录下递归查找文件名，存在返回 0，不存在返回 1
find_file() {
  local dir="$1"
  local name="$2"
  if [ ! -d "$dir" ]; then
    return 1
  fi
  local match
  match=$(find "$dir" -type f -name "$name" -print -quit 2>/dev/null || true)
  [ -n "$match" ]
}

# 打印单项检查结果，失败时将全局 FAIL 置 1
report() {
  local status="$1"
  local message="$2"
  if [ "$status" = "PASS" ]; then
    echo "  PASS: $message"
  else
    echo "  FAIL: $message"
    FAIL=1
  fi
}

# 1. 验证 AetherWatch 目录与核心源文件
echo "[1/4] 检查 AetherWatch 目录与核心源文件"
if [ -d "$WATCH_DIR" ]; then
  report PASS "目录存在: $WATCH_DIR"
  for f in "${WATCH_CORE_FILES[@]}"; do
    if find_file "$WATCH_DIR" "$f"; then
      report PASS "文件存在: $WATCH_DIR/**/$f"
    else
      report FAIL "缺失文件: $WATCH_DIR/**/$f"
    fi
  done
else
  report FAIL "目录缺失: $WATCH_DIR"
fi
echo ""

# 2. 验证 AetherWidgets 目录与核心源文件
echo "[2/4] 检查 AetherWidgets 目录与核心源文件"
if [ -d "$WIDGET_DIR" ]; then
  report PASS "目录存在: $WIDGET_DIR"
  for f in "${WIDGET_CORE_FILES[@]}"; do
    if find_file "$WIDGET_DIR" "$f"; then
      report PASS "文件存在: $WIDGET_DIR/**/$f"
    else
      report FAIL "缺失文件: $WIDGET_DIR/**/$f"
    fi
  done
else
  report FAIL "目录缺失: $WIDGET_DIR"
fi
echo ""

# 3. 验证 Xcode project scheme 列表包含 AetherWatch 与 AetherWidgets
echo "[3/4] 检查 Xcode scheme 列表"
if [ ! -d "$PROJECT_FILE" ]; then
  report FAIL "Xcode project 不存在: $PROJECT_FILE"
else
  report PASS "Xcode project 存在: $PROJECT_FILE"
  # 优先通过 xcodebuild -list 验证 scheme（CI 环境下 setup-xcode 后可用）
  SCHEMES_OUTPUT=$(xcodebuild -list -project "$PROJECT_FILE" 2>/dev/null || true)
  # 提取 "Schemes:" 段落（从该行之后到下一个空行之间的内容）
  SCHEMES_SECTION=$(echo "$SCHEMES_OUTPUT" | awk '/^[[:space:]]*Schemes:/{flag=1;next} /^[[:space:]]*$/ && flag{flag=0} flag' || true)
  if [ -n "$SCHEMES_SECTION" ]; then
    # xcodebuild 可用：从 Schemes 段落精确匹配 scheme 名
    for scheme in "AetherWatch" "AetherWidgets"; do
      if echo "$SCHEMES_SECTION" | grep -E "^[[:space:]]+${scheme}[[:space:]]*$" >/dev/null; then
        report PASS "scheme 存在: $scheme (xcodebuild)"
      else
        report FAIL "scheme 缺失: $scheme (xcodebuild)"
      fi
    done
  else
    # xcodebuild 不可用（如本地仅安装 Command Line Tools）：回退到检查 shared scheme 文件
    SCHEMES_DIR="$PROJECT_FILE/xcshareddata/xcschemes"
    for scheme in "AetherWatch" "AetherWidgets"; do
      if [ -f "$SCHEMES_DIR/${scheme}.xcscheme" ]; then
        report PASS "scheme 存在: $scheme (shared xcscheme)"
      else
        report FAIL "scheme 缺失: $scheme (shared xcscheme)"
      fi
    done
  fi
fi
echo ""

# 4. 验证 entitlements 文件包含 App Group 配置
echo "[4/4] 检查 entitlements App Group 配置"
for ent in "$WATCH_DIR/AetherWatch.entitlements" "$WIDGET_DIR/AetherWidgets.entitlements"; do
  if [ ! -f "$ent" ]; then
    report FAIL "entitlements 文件缺失: $ent"
    continue
  fi
  if grep -q "$APP_GROUP" "$ent"; then
    report PASS "App Group 配置存在: $ent ($APP_GROUP)"
  else
    report FAIL "App Group 配置缺失: $ent (期望包含 $APP_GROUP)"
  fi
done
echo ""

# 总结
echo "=== 总结 ==="
if [ "$FAIL" -eq 0 ]; then
  echo "PASS: 所有 Watch/Widget target 检查项通过"
  exit 0
else
  echo "FAIL: 存在检查项未通过，请查看上方标记 FAIL 的条目"
  exit 1
fi
