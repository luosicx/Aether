#!/usr/bin/env bash
#
# SwiftLint CI 集成脚本 for Aether 项目
# 在 CI 中运行 SwiftLint 检查代码风格
#

set -uo pipefail

# 切换到项目根目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

# 检查 swiftlint 是否安装（未安装时打印提示并退出 0，不阻塞 CI）
if ! command -v swiftlint >/dev/null 2>&1; then
    echo "⚠️  SwiftLint 未安装，跳过检查。"
    echo "   安装方法: brew install swiftlint"
    echo "   或访问: https://github.com/realm/SwiftLint"
    exit 0
fi

echo "🔍 运行 SwiftLint 检查..."
echo "   配置文件: .swiftlint.yml"
echo ""

# 运行 SwiftLint（使用 || true 防止违规导致脚本提前退出）
OUTPUT="$(swiftlint lint --config .swiftlint.yml --reporter github-actions-logging 2>&1)" || true
echo "$OUTPUT"

# 统计 warning 和 error 数量（grep -c 在无匹配时返回 1，用 || true 兜底）
WARNING_COUNT=$(echo "$OUTPUT" | grep -c "^::warning" || true)
ERROR_COUNT=$(echo "$OUTPUT" | grep -c "^::error" || true)

echo ""
echo "📊 SwiftLint 结果统计:"
echo "   Warnings: $WARNING_COUNT"
echo "   Errors:   $ERROR_COUNT"

# 如果有 error，退出码 1；只有 warning 则退出码 0
if [ "$ERROR_COUNT" -gt 0 ]; then
    echo ""
    echo "❌ SwiftLint 检查未通过（存在 $ERROR_COUNT 个 error）"
    exit 1
fi

if [ "$WARNING_COUNT" -gt 0 ]; then
    echo ""
    echo "⚠️  SwiftLint 检查通过，但存在 $WARNING_COUNT 个 warning"
fi

echo ""
echo "✅ SwiftLint 检查完成"
exit 0
