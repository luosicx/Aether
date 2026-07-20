#!/bin/bash
set -euo pipefail
# 文档一致性检查：对比代码中的 i18n key 数、工具数、测试数与文档声明
# 检查 README.md / doc/OPTIMIZATION.md / doc/ARCHITECTURE.md 三个文件
# 数字不一致时 exit 1，输出差异详情

FAIL=0
echo "=== 文档一致性检查 ==="
echo ""

# 1. 从代码中统计实际数字
# i18n key 数（xcstrings JSON 中 "strings" 下的条目数）
# M-C12: 原 `|| echo "0"` 在 python3 失败时会产生 "0\n0"（python 输出 + echo 输出），
#        导致后续算术运算报 "syntax error: invalid arithmetic operator"。
#        改用 `|| true`：保留 python 的 stdout（失败时为空），再在算术运算前用 ${VAR:-0} 兜底。
I18N_KEYS=$(python3 -c "import json; data=json.load(open('Aether/Resources/Localizable.xcstrings')); print(len(data.get('strings',{})))" 2>/dev/null || true)
I18N_KEYS=${I18N_KEYS:-0}

# 工具数（跨平台工具 + macOS 独有工具）
# 注：ToolRegistry.swift 中 registerBatch 内部的 `register(tool: tool)` 是辅助调用，不算工具注册；
# 用精确匹配 `register(tool: <TypeName>())` 形式才能准确计数。
# M-C12: grep -c 在无匹配时退出码 1 + stdout "0"，`|| echo "0"` 会产生 "0\n0" 触发算术错误。
#        改用 `|| true` 保留 grep 的 "0" 输出。
CROSS_TOOLS=$(grep -cE '^\s*register\(tool:\s*[A-Z][A-Za-z0-9_]*\(\)\)' Aether/Services/Tools/ToolRegistry.swift 2>/dev/null || true)
CROSS_TOOLS=${CROSS_TOOLS:-0}
MACOS_TOOLS=$(grep -cE '^\s*register\(tool:\s*[A-Z][A-Za-z0-9_]*\(\)\)' Aether/Services/Tools/ToolRegistry+macOS.swift 2>/dev/null || true)
MACOS_TOOLS=${MACOS_TOOLS:-0}
TOOL_COUNT=$((CROSS_TOOLS + MACOS_TOOLS))

# 测试数：精确匹配 XCTest 测试方法定义 `func testXxx(`，避免匹配注释或 helper
# 注：grep -E | wc -l 模式下，grep 无匹配退出 1，pipefail 让管道退出 1，
#     `|| true` 防止 set -e 退出脚本，wc -l 输出 "0" 被保留。
TEST_COUNT=$(grep -rhE '^\s*func test\w+\s*\(' AetherTests/ 2>/dev/null | wc -l | tr -d ' ' || true)
TEST_COUNT=${TEST_COUNT:-0}

echo "代码统计:"
echo "  i18n keys: $I18N_KEYS"
echo "  工具数: $TOOL_COUNT (跨平台=$CROSS_TOOLS + macOS=$MACOS_TOOLS)"
echo "  测试数: $TEST_COUNT"
echo ""

# 2. 定义文档检查函数
#    从文件中提取 i18n / tools / tests 声明数字并与代码对比
#    优先使用 <!-- doc-stats --> 标记行；没有则用 grep 从文本提取
check_doc_file() {
  local filepath="$1"

  if [ ! -f "$filepath" ]; then
    echo "检查 $filepath: 文件不存在，跳过"
    echo ""
    return
  fi

  local doc_stats file_i18n file_tools file_tests
  doc_stats=$(grep 'doc-stats:' "$filepath" 2>/dev/null || echo "")

  if [ -n "$doc_stats" ]; then
    # 从 <!-- doc-stats: i18n=NNN tools=NNN tests=NNN --> 标记行提取
    file_i18n=$(echo "$doc_stats" | sed -n 's/.*i18n=\([0-9]*\).*/\1/p')
    file_tools=$(echo "$doc_stats" | sed -n 's/.*tools=\([0-9]*\).*/\1/p')
    file_tests=$(echo "$doc_stats" | sed -n 's/.*tests=\([0-9]*\).*/\1/p')
  else
    # 无 doc-stats 标记，从文本中 grep 提取数字
    # i18n: 匹配 "NNN keys"
    file_i18n=$(grep -oE '[0-9]+ keys' "$filepath" 2>/dev/null | head -1 | grep -oE '[0-9]+' || echo "")
    # tools: 匹配 "共 NN 个"（首次出现）
    file_tools=$(grep -oE '共 [0-9]+ 个' "$filepath" 2>/dev/null | head -1 | grep -oE '[0-9]+' || echo "")
    # tests: 匹配 "UT NNNN" 或 "NNNN 用例"（首次出现）
    file_tests=$(grep -oE 'UT [0-9]+|[0-9]+ 用例' "$filepath" 2>/dev/null | head -1 | grep -oE '[0-9]+' || echo "")
  fi

  echo "检查 $filepath:"

  if [ -n "$file_i18n" ]; then
    if [ "$file_i18n" != "$I18N_KEYS" ]; then
      echo "  FAIL: i18n key 数不一致 (文件=$file_i18n, 代码=$I18N_KEYS)"
      FAIL=1
    else
      echo "  i18n=$file_i18n ✓"
    fi
  fi

  if [ -n "$file_tools" ]; then
    if [ "$file_tools" != "$TOOL_COUNT" ]; then
      echo "  FAIL: 工具数不一致 (文件=$file_tools, 代码=$TOOL_COUNT)"
      FAIL=1
    else
      echo "  tools=$file_tools ✓"
    fi
  fi

  if [ -n "$file_tests" ]; then
    if [ "$file_tests" != "$TEST_COUNT" ]; then
      echo "  FAIL: 测试数不一致 (文件=$file_tests, 代码=$TEST_COUNT)"
      FAIL=1
    else
      echo "  tests=$file_tests ✓"
    fi
  fi

  echo ""
}

# 3. 检查三个文档文件
check_doc_file "README.md"
check_doc_file "doc/OPTIMIZATION.md"
check_doc_file "doc/ARCHITECTURE.md"

# 4. 输出最终结果
if [ $FAIL -eq 0 ]; then
  echo "PASS: 所有文档数字与代码一致"
  exit 0
else
  echo "FAIL: 文档数字与代码不一致，请检查上述标记 FAIL 的条目"
  exit 1
fi
