#!/bin/bash
# 安装 Git native hooks（P1-13 / H-C1）
#
# 适用场景：不使用 Python pre-commit 框架的开发者。
# 安装 pre-commit 框架方式：见 .pre-commit-config.yaml
#
# 安装的 hooks：
# - pre-commit: 提交前检查（大文件、私钥、调试代码、合并冲突标记）
#
# 用法：
#   make install-hooks   # 通过 Makefile
#   bash scripts/install-git-hooks.sh  # 直接调用
#
# 卸载：
#   rm .git/hooks/pre-commit

set -euo pipefail

REPO_ROOT=$(git rev-parse --show-toplevel)
HOOKS_DIR="$REPO_ROOT/.git/hooks"
PRE_COMMIT_HOOK="$HOOKS_DIR/pre-commit"

mkdir -p "$HOOKS_DIR"

cat > "$PRE_COMMIT_HOOK" <<'EOF'
#!/bin/bash
# Pre-commit hook（Aether 项目 / P1-13 H-C1）
# 安装方式：bash scripts/install-git-hooks.sh 或 make install-hooks

set -e

# 1. 大文件提交防护（>1MB，排除 xcframework 与截图）
MAX_SIZE=$((1024 * 1024))  # 1MB
LARGE_FILES=()
while IFS= read -r file; do
    # 跳过已删除文件
    [ -f "$file" ] || continue
    # 跳过 xcframework 和截图
    case "$file" in
        Packages/AetherCore/aether_core.xcframework/*) continue ;;
        screenshots/*) continue ;;
        Aether/Resources/Assets.xcassets/AppIcon.appiconset/*) continue ;;
    esac
    size=$(wc -c < "$file" | tr -d ' ')
    if [ "$size" -gt "$MAX_SIZE" ]; then
        LARGE_FILES+=("$file (${size} bytes)")
    fi
done < <(git diff --cached --name-only --diff-filter=ACM)

if [ ${#LARGE_FILES[@]} -gt 0 ]; then
    echo "❌ 检测到大文件提交（>1MB），请考虑使用 Git LFS 或排除："
    printf '  %s\n' "${LARGE_FILES[@]}"
    echo ""
    echo "如需提交二进制资源（图标、截图），请添加到 .gitattributes 中标记为 binary。"
    exit 1
fi

# 2. 私钥泄露检测
KEY_PATTERNS=(
    '-----BEGIN .* PRIVATE KEY-----'
    'aws_secret_access_key'
    'AKIA[0-9A-Z]{16}'  # AWS access key ID
    'ghp_[A-Za-z0-9]{36}'  # GitHub personal access token
    'gho_[A-Za-z0-9]{36}'  # GitHub OAuth token
    'sk-[A-Za-z0-9]{20}'  # OpenAI/DeepSeek API key prefix
)

KEY_HITS=()
while IFS= read -r file; do
    [ -f "$file" ] || continue
    # 跳过测试与示例（使用 fake/test 密钥）
    case "$file" in
        Examples/*) continue ;;
        AetherTests/*) continue ;;
        CloudflareWorkers/test/*) continue ;;
        *.md) continue ;;
    esac
    for pattern in "${KEY_PATTERNS[@]}"; do
        if grep -qE "$pattern" "$file" 2>/dev/null; then
            KEY_HITS+=("$file (匹配模式: $pattern)")
        fi
    done
done < <(git diff --cached --name-only --diff-filter=ACM)

if [ ${#KEY_HITS[@]} -gt 0 ]; then
    echo "❌ 检测到疑似私钥/凭据泄露，请检查以下文件："
    printf '  %s\n' "${KEY_HITS[@]}"
    echo ""
    echo "如为测试用 fake 密钥，请将文件路径加入 scripts/install-git-hooks.sh 排除列表。"
    exit 1
fi

# 3. 合并冲突标记残留检测
CONFLICT_FILES=()
while IFS= read -r file; do
    [ -f "$file" ] || continue
    if grep -qE '^(<<<<<<<|>>>>>>>|=======) ' "$file" 2>/dev/null; then
        CONFLICT_FILES+=("$file")
    fi
done < <(git diff --cached --name-only --diff-filter=ACM)

if [ ${#CONFLICT_FILES[@]} -gt 0 ]; then
    echo "❌ 检测到未解决的合并冲突标记："
    printf '  %s\n' "${CONFLICT_FILES[@]}"
    exit 1
fi

# 4. SwiftFormat 校验（如已安装）
if command -v swiftformat >/dev/null 2>&1; then
    SWIFT_FILES=$(git diff --cached --name-only --diff-filter=ACM -- '*.swift' || true)
    if [ -n "$SWIFT_FILES" ]; then
        # 排除 AetherRust 生成代码和示例
        FILTERED=$(echo "$SWIFT_FILES" | grep -vE '^(Packages/AetherCore/Sources/AetherRust/|Examples/)' || true)
        if [ -n "$FILTERED" ]; then
            if ! swiftformat --config .swiftformat --check $FILTERED; then
                echo "❌ SwiftFormat 校验失败，请运行：swiftformat --config .swiftformat <files>"
                exit 1
            fi
        fi
    fi
fi

# 5. SwiftLint 校验（如已安装）
if command -v swiftlint >/dev/null 2>&1; then
    SWIFT_FILES=$(git diff --cached --name-only --diff-filter=ACM -- '*.swift' || true)
    if [ -n "$SWIFT_FILES" ]; then
        FILTERED=$(echo "$SWIFT_FILES" | grep -vE '^(Packages/AetherCore/Sources/AetherRust/|Examples/)' || true)
        if [ -n "$FILTERED" ]; then
            if ! swiftlint lint --strict --config .swiftlint.yml $FILTERED; then
                echo "❌ SwiftLint 校验失败，请修复违规项"
                exit 1
            fi
        fi
    fi
fi

echo "✅ Pre-commit 检查通过"
exit 0
EOF

chmod +x "$PRE_COMMIT_HOOK"

echo "✅ Git pre-commit hook 已安装到 $PRE_COMMIT_HOOK"
echo ""
echo "卸载方式：rm $PRE_COMMIT_HOOK"
echo "替代方案（Python pre-commit 框架）：见 .pre-commit-config.yaml"
