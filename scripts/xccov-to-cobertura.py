#!/usr/bin/env python3
# xccov-to-cobertura.py
#
# 将 xccov 归档（每行真实执行次数）转换为 SonarCloud 兼容的 cobertura XML
# （<file><lineToCover> 格式，与 merge-coverage.py 期望一致）。
#
# 数据来源必须是 `xcrun xccov view --archive --json`：
#   - 只有 archive 格式包含每一行是否可执行（isExecutable）与执行次数（executionCount）；
#   - `--report` 格式只给文件级汇总（可执行单元计数），旧版脚本拿它按文件行数
#     等比缩放生成 lineToCover，等于伪造逐行覆盖，Sonar 的数字因此失真。
#
# 用法：
#   xcrun xccov view --archive --json TestResults.xcresult > /tmp/xccov_archive.json
#   python3 scripts/xccov-to-cobertura.py /tmp/xccov_archive.json coverage-report/coverage.xml
#
# 也可以直接传 .xcresult（脚本会自行调用 xccov），便于本地调试：
#   python3 scripts/xccov-to-cobertura.py TestResults.xcresult coverage-report/coverage.xml
#
# 只输出可执行行的真实覆盖状态；不可执行行不写入 lineToCover。

import json
import os
import subprocess
import sys
from xml.sax.saxutils import escape

# 覆盖率排除清单：纯 SwiftUI 视图、设计 token、App 入口、协议定义、UI 测试目标、
# watchOS、MLX 推理引擎、HealthKit、WatchConnectivity、Crash、Spotlight 等均无法在
# 模拟器单测中有效覆盖。
EXCLUDE_PATTERNS = [
    "/Views/", "/DesignSystem/", "/App/AetherApp",
    "/Protocols/", "/Actors/", "/AetherUITests/",
    "/AetherWatch/", "/AetherTests/",
    "/AetherDesign/", "/AetherUI/", "/AppIntents/",
    "/OnDevice/", "/Health/", "/Connectivity/",
    "/Crash/", "/Search/",
]


def load_archive(input_path):
    """读取 xccov archive JSON；输入为 .xcresult 时调用 xccov 导出。"""
    if input_path.endswith(".json"):
        with open(input_path, "r", encoding="utf-8") as f:
            return json.load(f)
    result = subprocess.run(
        ["xcrun", "xccov", "view", "--archive", "--json", input_path],
        check=True,
        capture_output=True,
        text=True,
    )
    return json.loads(result.stdout)


def collect_files(archive, project_root):
    """把 archive 转换为 [(rel_path, {line: covered})]，仅保留主源码目录。"""
    files = []
    for abs_path, entries in archive.items():
        try:
            rel_path = os.path.relpath(abs_path, project_root)
        except ValueError:
            rel_path = abs_path
        if not rel_path.startswith("Aether/"):
            continue
        if any(p in rel_path for p in EXCLUDE_PATTERNS):
            continue

        lines = {}
        for entry in entries or []:
            if not entry.get("isExecutable"):
                continue
            line = entry.get("line")
            if not isinstance(line, int) or line <= 0:
                continue
            lines[line] = (entry.get("executionCount") or 0) > 0
        if lines:
            files.append((rel_path, lines))

    files.sort(key=lambda item: item[0])
    return files


def write_cobertura_xml(output_xml, files):
    """写入 cobertura XML（仅可执行行），返回 (covered, total)。"""
    total_covered = sum(covered for _, lines in files for covered in lines.values())
    total_valid = sum(len(lines) for _, lines in files)

    with open(output_xml, "w", encoding="utf-8") as f:
        if not files:
            f.write('<coverage version="1"></coverage>\n')
        else:
            f.write('<coverage version="1">\n')
            for rel_path, lines in files:
                f.write(f'  <file path="{escape(rel_path)}">\n')
                for ln in sorted(lines):
                    covered = "true" if lines[ln] else "false"
                    f.write(f'    <lineToCover lineNumber="{ln}" covered="{covered}"/>\n')
                f.write('  </file>\n')
            f.write('</coverage>\n')

    rate = total_covered / total_valid if total_valid else 0
    print(f"coverage.xml written: line-rate={rate:.4f} ({total_covered}/{total_valid} executable lines)")
    print(f"Files: {len(files)}")
    return total_covered, total_valid


def main():
    if len(sys.argv) != 3:
        print(
            "Usage: xccov-to-cobertura.py <xccov-archive.json|TestResults.xcresult> <output.xml>",
            file=sys.stderr,
        )
        sys.exit(1)

    input_path = sys.argv[1]
    output_xml = sys.argv[2]

    try:
        archive = load_archive(input_path)
    except (OSError, ValueError, subprocess.CalledProcessError) as err:
        print(f"WARNING: cannot load xccov archive ({err}); writing empty coverage.xml", file=sys.stderr)
        write_cobertura_xml(output_xml, [])
        return

    files = collect_files(archive, os.getcwd())
    write_cobertura_xml(output_xml, files)


if __name__ == "__main__":
    main()
