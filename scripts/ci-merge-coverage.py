#!/usr/bin/env python3
"""合并多个 cobertura.xml 覆盖率报告。

用法: python3 ci-merge-coverage.py <output.xml> <input1.xml> [input2.xml] ...

合并策略：对同一源文件的同一行，任一分片 covered=true 则合并后 covered=true。
适用于测试分片场景：不同分片覆盖同一源文件的不同代码路径，合并后得到完整覆盖率。
"""
import sys
import os
from xml.etree import ElementTree as ET
from collections import defaultdict


def merge_coverage(output_path, input_paths):
    """合并多个 cobertura.xml 文件。

    file_path -> {line_number: covered(bool)}
    同一文件同一行，任一报告 covered=true 则合并为 true。
    """
    # file_path -> {line_number: covered}
    merged = defaultdict(dict)

    for inp in input_paths:
        if not os.path.exists(inp):
            print(f"警告: 覆盖率文件不存在，跳过: {inp}", file=sys.stderr)
            continue
        try:
            tree = ET.parse(inp)
        except ET.ParseError as e:
            print(f"警告: 解析失败，跳过 {inp}: {e}", file=sys.stderr)
            continue
        root = tree.getroot()
        for f in root.findall('file'):
            path = f.get('path')
            if not path:
                continue
            for line in f.findall('lineToCover'):
                ln = int(line.get('lineNumber', '0'))
                covered = line.get('covered') == 'true'
                # 任一分片 covered=true 则合并为 true
                if ln > 0:
                    if ln in merged[path]:
                        merged[path][ln] = merged[path][ln] or covered
                    else:
                        merged[path][ln] = covered

    if not merged:
        print("错误: 没有可合并的覆盖率数据", file=sys.stderr)
        sys.exit(1)

    # 生成合并后的 cobertura.xml
    # 文件按路径排序，行号按顺序排列
    with open(output_path, 'w', encoding='utf-8') as f:
        f.write('<coverage version="1">\n')
        total_covered = 0
        total_lines = 0
        for path in sorted(merged.keys()):
            lines = merged[path]
            f.write(f'  <file path="{path}">\n')
            for ln in sorted(lines.keys()):
                covered = "true" if lines[ln] else "false"
                f.write(f'    <lineToCover lineNumber="{ln}" covered="{covered}"/>\n')
                if lines[ln]:
                    total_covered += 1
                total_lines += 1
            f.write(f'  </file>\n')
        f.write('</coverage>\n')

    rate = total_covered / total_lines if total_lines else 0
    print(f"合并完成: {output_path}")
    print(f"总覆盖率: {rate:.4f} ({total_covered}/{total_lines} lines, "
          f"{len(merged)} files)")


def main():
    if len(sys.argv) < 3:
        print("用法: python3 ci-merge-coverage.py <output.xml> <input1.xml> "
              "[input2.xml] ...", file=sys.stderr)
        sys.exit(1)
    output_path = sys.argv[1]
    input_paths = sys.argv[2:]
    merge_coverage(output_path, input_paths)


if __name__ == "__main__":
    main()
