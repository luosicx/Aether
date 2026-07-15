#!/bin/bash
#
# generate-tokens.sh — 调用三个 Python 脚本，从 DesignTokens/tokens.json
# 生成 Swift / Kotlin / C# 三端的设计令牌文件。
#
# 用法：
#   bash scripts/generate-tokens.sh
#
# 生成产物：
#   - Packages/AetherCore/Sources/AetherDesign/GeneratedTokens.swift
#   - android/app/src/main/java/com/aether/design/DesignTokens.kt
#   - windows/Aether.Windows/Design/DesignTokens.cs
#

set -euo pipefail

# 切换到项目根目录（脚本位于 scripts/ 下，向上走一层）
cd "$(dirname "$0")/.."

PROJECT_ROOT="$(pwd)"
TOKENS_JSON="$PROJECT_ROOT/DesignTokens/tokens.json"
SCRIPTS_DIR="$PROJECT_ROOT/scripts"

# 输出路径
SWIFT_OUT="Packages/AetherCore/Sources/AetherDesign/GeneratedTokens.swift"
KOTLIN_OUT="android/app/src/main/java/com/aether/design/DesignTokens.kt"
CSHARP_OUT="windows/Aether.Windows/Design/DesignTokens.cs"

echo "==> 读取设计令牌单一真相源: $TOKENS_JSON"

if [[ ! -f "$TOKENS_JSON" ]]; then
    echo "错误：找不到 tokens.json: $TOKENS_JSON" >&2
    exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
    echo "错误：未找到 python3，请先安装 Python 3。" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Swift
# ---------------------------------------------------------------------------
echo "==> 生成 Swift 令牌 → $SWIFT_OUT"
mkdir -p "$(dirname "$SWIFT_OUT")"
python3 "$SCRIPTS_DIR/gen_swift_tokens.py" "$TOKENS_JSON" > "$SWIFT_OUT"

# ---------------------------------------------------------------------------
# Kotlin
# ---------------------------------------------------------------------------
echo "==> 生成 Kotlin 令牌 → $KOTLIN_OUT"
mkdir -p "$(dirname "$KOTLIN_OUT")"
python3 "$SCRIPTS_DIR/gen_kotlin_tokens.py" "$TOKENS_JSON" > "$KOTLIN_OUT"

# ---------------------------------------------------------------------------
# C#
# ---------------------------------------------------------------------------
echo "==> 生成 C# 令牌 → $CSHARP_OUT"
mkdir -p "$(dirname "$CSHARP_OUT")"
python3 "$SCRIPTS_DIR/gen_csharp_tokens.py" "$TOKENS_JSON" > "$CSHARP_OUT"

echo ""
echo "==> 全部生成完成："
echo "    Swift:   $SWIFT_OUT"
echo "    Kotlin:  $KOTLIN_OUT"
echo "    C#:      $CSHARP_OUT"
