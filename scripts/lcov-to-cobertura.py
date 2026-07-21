#!/usr/bin/env python3
# lcov-to-cobertura.py
#
# 将 llvm-cov 导出的 lcov 格式覆盖率转换为 cobertura XML（<class><lines><line hits> 格式），
# 供 merge-coverage.py 合并到 SonarCloud 总覆盖率报告。
#
# 用法：
#   xcrun llvm-cov export -format=lcov -instr-profile=default.profdata AetherSDKTests > coverage.lcov
#   python3 scripts/lcov-to-cobertura.py coverage.lcov coverage.xml
#
# 背景：
#   Xcode 26.3 的 llvm-cov 不再支持 cobertura 格式输出，仅支持 text/lcov/html。
#   因此先生成 lcov，再用本脚本转为 cobertura XML。

import os
import sys
from xml.sax.saxutils import escape


def parse_lcov(lcov_path):
    """解析 lcov：返回 [(src_file, [(lineno, hits), ...]), ...]。

    lcov 格式：
        SF:path/to/file.swift
        DA:lineNumber,hits
        DA:lineNumber,hits
        end_of_record
    """
    records = []
    cur_file = None
    cur_lines = []
    with open(lcov_path, 'r', encoding='utf-8', errors='replace') as f:
        for line in f:
            line = line.rstrip('\n')
            if line.startswith('SF:'):
                cur_file = line[3:]
                cur_lines = []
            elif line.startswith('DA:'):
                parts = line[3:].split(',')
                if len(parts) >= 2:
                    try:
                        lineno = int(parts[0])
                        hits = int(parts[1])
                        cur_lines.append((lineno, hits))
                    except ValueError:
                        pass
            elif line == 'end_of_record':
                if cur_file is not None:
                    records.append((cur_file, cur_lines))
                cur_file, cur_lines = None, []
    return records


def to_relative_path(src_file, project_root):
    """将绝对路径转为相对路径，匹配 SonarCloud 的 sonar.sources 基准。"""
    fname = src_file
    if os.path.isabs(fname):
        try:
            fname = os.path.relpath(fname, project_root)
        except ValueError:
            pass
    return fname


def write_cobertura_xml(xml_path, records, project_root):
    """写入 cobertura XML（<class><lines><line hits> 格式）。"""
    with open(xml_path, 'w', encoding='utf-8') as f:
        f.write('<?xml version="1.0" ?>\n')
        f.write('<coverage version="6.3">\n')
        f.write('  <packages>\n')
        f.write('    <package>\n')
        f.write('      <classes>\n')
        for src_file, lines in records:
            fname = to_relative_path(src_file, project_root)
            f.write(f'        <class filename="{escape(fname)}">\n')
            f.write('          <lines>\n')
            for lineno, hits in lines:
                f.write(f'            <line number="{lineno}" hits="{hits}"/>\n')
            f.write('          </lines>\n')
            f.write('        </class>\n')
        f.write('      </classes>\n')
        f.write('    </package>\n')
        f.write('  </packages>\n')
        f.write('</coverage>\n')
    print(f"Generated cobertura XML with {len(records)} files")


def main():
    if len(sys.argv) < 3:
        print("Usage: lcov-to-cobertura.py <input.lcov> <output.xml>", file=sys.stderr)
        sys.exit(1)
    lcov_path = sys.argv[1]
    xml_path = sys.argv[2]
    project_root = os.environ.get('GITHUB_WORKSPACE', os.getcwd())

    records = parse_lcov(lcov_path)
    write_cobertura_xml(xml_path, records, project_root)


if __name__ == "__main__":
    main()
