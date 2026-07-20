#!/usr/bin/env python3
# extract-release-notes.py
#
# 从 doc/CHANGELOG.md 提取指定版本的发布说明。
#
# 用法：
#   python3 scripts/extract-release-notes.py <version> [<changelog_path>]
#
# 输出：对应版本段落的正文（去掉 `## [version]` 标题行）。
# 未找到对应版本时，输出 `## Aether v{version}` 作为 fallback。

import os
import re
import sys


def extract_notes(version, changelog_path):
    if not os.path.exists(changelog_path):
        return f"## Aether v{version}"
    with open(changelog_path, 'r', encoding='utf-8') as f:
        text = f.read()
    # 匹配 ## [1.0.0] 或 ## 1.0.0 格式
    pattern = rf"(?m)^## (?:\[)?{re.escape(version)}(?:\])?[^\n]*\n(?:(?!^## ).)+"
    m = re.search(pattern, text, re.S)
    if not m:
        return f"## Aether v{version}"
    body = re.sub(rf"(?m)^## (?:\[)?{re.escape(version)}(?:\])?[^\n]*\n", "", m.group(0))
    return body.strip()


def main():
    if len(sys.argv) < 2:
        print("Usage: extract-release-notes.py <version> [<changelog_path>]", file=sys.stderr)
        sys.exit(1)
    version = sys.argv[1]
    changelog_path = sys.argv[2] if len(sys.argv) > 2 else "doc/CHANGELOG.md"
    print(extract_notes(version, changelog_path))


if __name__ == "__main__":
    main()
