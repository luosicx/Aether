#!/usr/bin/env python3
# xccov-to-cobertura.py
#
# 将 `xcrun xccov view --report` 的文本输出转换为 SonarCloud 兼容的 cobertura XML
# （<file><lineToCover> 格式，与 merge-coverage.py 期望一致）。
#
# 用法：
#   xcrun xccov view --report TestResults.xcresult > /tmp/coverage_report.txt
#   python3 scripts/xccov-to-cobertura.py /tmp/coverage_report.txt coverage-report/coverage.xml
#
# 主要逻辑：
#   1. 正则匹配文本中的 "/abs/path.swift  pct% (cov/tot)" 行
#   2. 排除 Views/DesignSystem/App entry/Protocols/Actors/UITests/Watch 等无法单测的目录
#   3. 读取实际源文件行数，按比例缩放 cov/tot（xccov 的 tot 是可执行单元数，可能超过文件行数）
#   4. 输出 cobertura XML，每行一个 <lineToCover>

import os
import re
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

PATTERN = re.compile(r"^\s+(/\S+\.swift)\s+([\d.]+)%\s+\((\d+)/(\d+)\)", re.MULTILINE)


def parse_xccov_text(text, project_root):
    """解析 xccov 文本，返回 (files, total_covered, total_valid)。

    files: list of (rel_path, scaled_cov, scaled_tot)
    """
    files = []
    total_covered = 0
    total_valid = 0

    for m in PATTERN.finditer(text):
        abs_path = m.group(1)
        cov = int(m.group(3))
        tot = int(m.group(4))
        try:
            rel_path = os.path.relpath(abs_path, project_root)
        except ValueError:
            rel_path = abs_path
        # 仅纳入 Aether/ 主源码目录
        if not rel_path.startswith("Aether/"):
            continue
        if any(p in rel_path for p in EXCLUDE_PATTERNS):
            continue
        # 读取实际源文件行数，确保 lineNumber 不超过文件行数
        abs_file_path = os.path.join(project_root, rel_path)
        try:
            with open(abs_file_path, 'r') as sf:
                actual_lines = sum(1 for _ in sf)
        except (IOError, OSError):
            # M-C8: 文件读取失败时跳过该文件，避免 tot > 文件实际行数导致
            # lineNumber 越界被 SonarCloud 拒绝（原代码降级为 tot 会触发此问题）。
            print(f"WARNING: cannot read {rel_path}, skipping from coverage report", file=sys.stderr)
            continue
        if actual_lines == 0:
            print(f"WARNING: {rel_path} is empty, skipping from coverage report", file=sys.stderr)
            continue
        # 确保 lineNumber 不超过文件实际行数：取 min(tot, actual_lines)
        max_lines = min(tot, actual_lines)
        if tot > 0:
            scaled_cov = int(round(cov * max_lines / tot))
        else:
            scaled_cov = 0
        scaled_tot = max_lines
        files.append((rel_path, scaled_cov, scaled_tot))
        total_covered += scaled_cov
        total_valid += scaled_tot

    return files, total_covered, total_valid


def write_cobertura_xml(output_xml, files, total_covered, total_valid):
    """写入 cobertura XML（<file><lineToCover> 格式）。"""
    if total_valid == 0:
        print("WARNING: no coverage data found in report, using empty coverage.xml", file=sys.stderr)
        with open(output_xml, 'w', encoding='utf-8') as f:
            f.write('<coverage version="1"></coverage>\n')
        return
    with open(output_xml, 'w', encoding='utf-8') as f:
        f.write('<coverage version="1">\n')
        for rel_path, f_cov, f_tot in files:
            f.write(f'  <file path="{escape(rel_path)}">\n')
            for ln in range(1, f_tot + 1):
                covered = "true" if ln <= f_cov else "false"
                f.write(f'    <lineToCover lineNumber="{ln}" covered="{covered}"/>\n')
            f.write(f'  </file>\n')
        f.write('</coverage>\n')
    rate = total_covered / total_valid if total_valid else 0
    print(f"coverage.xml written: line-rate={rate:.4f} ({total_covered}/{total_valid} lines)")
    print(f"Sample paths: {[f[0] for f in files[:3]]}")


def main():
    if len(sys.argv) < 3:
        print("Usage: xccov-to-cobertura.py <xccov-report.txt> <output.xml>", file=sys.stderr)
        sys.exit(1)
    report_path = sys.argv[1]
    output_xml = sys.argv[2]

    with open(report_path, 'r') as f:
        text = f.read()

    project_root = os.getcwd()
    files, total_covered, total_valid = parse_xccov_text(text, project_root)
    write_cobertura_xml(output_xml, files, total_covered, total_valid)


if __name__ == "__main__":
    main()
