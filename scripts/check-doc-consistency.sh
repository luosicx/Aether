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
I18N_KEYS=$(python3 -c "import json; data=json.load(open('Aether/Resources/Localizable.xcstrings')); print(len(data.get('strings',{})))" 2>/dev/null || echo "0")

# 工具数（跨平台工具 + macOS 独有工具）
CROSS_TOOLS=$(grep -c '^\s*register(tool:' Aether/Services/Tools/ToolRegistry.swift 2>/dev/null || echo "0")
MACOS_TOOLS=$(grep -c '^\s*register(tool:' Aether/Services/Tools/ToolRegistry+macOS.swift 2>/dev/null || echo "0")
TOOL_COUNT=$((CROSS_TOOLS + MACOS_TOOLS))

# 测试数
TEST_COUNT=$(grep -r "func test" AetherTests/ 2>/dev/null | grep -c "func test" || echo "0")

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
