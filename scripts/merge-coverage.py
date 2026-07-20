#!/usr/bin/env python3
# merge-coverage.py
#
# 合并多源覆盖率报告为统一的 cobertura XML（<file><lineToCover> 格式），
# 供 SonarCloud Scan 上传。
#
# 用法：
#   python3 scripts/merge-coverage.py <ios.xml> <macos.xml> <rust.xml> <sdk.xml> <output.xml>
#
# 支持两类输入格式：
#   - iOS / macOS / AetherSDK：SonarCloud 兼容的 <file><lineToCover> 格式
#   - Rust / AetherSDK（lcov 转换）：cobertura <class><lines><line hits> 格式
#
# 合并策略：union —— 同一行任一源覆盖即视为覆盖。

import sys
import xml.etree.ElementTree as ET


def parse_swift_coverage(path):
    """解析 iOS/macOS cobertura 风格 XML（<file><lineToCover>）。

    返回 {filepath: {lineno: covered_bool}}。
    """
    files = {}
    try:
        root = ET.parse(path).getroot()
    except (ET.ParseError, FileNotFoundError):
        return files
    for f in root.findall('file'):
        fpath = f.get('path')
        lines = {}
        for l in f.findall('lineToCover'):
            try:
                ln = int(l.get('lineNumber'))
            except (TypeError, ValueError):
                continue
            lines[ln] = l.get('covered') == 'true'
        files[fpath] = lines
    return files


def parse_cobertura_class(cls):
    """解析 cobertura <class> 元素的 <lines> 子节点。

    返回 {lineno: covered_bool}。
    """
    lines = {}
    lines_el = cls.find("lines")
    if lines_el is None:
        return lines
    for l in lines_el.findall("line"):
        try:
            ln = int(l.get("number", "0"))
        except (TypeError, ValueError):
            continue
        try:
            hits = int(l.get("hits", "0"))
        except (TypeError, ValueError):
            hits = 0
        lines[ln] = hits > 0
    return lines


def parse_rust_coverage(path):
    """解析 Rust cargo-llvm-cov cobertura XML（<class filename><lines><line hits>）。

    返回 {filepath: {lineno: covered_bool}}。
    """
    files = {}
    try:
        root = ET.parse(path).getroot()
    except (ET.ParseError, FileNotFoundError):
        return files
    for cls in root.iter("class"):
        fpath = cls.get("filename")
        if not fpath:
            continue
        # cargo-llvm-cov 工作目录为 rust/，路径如 aether-core/src/chunk.rs
        # 需添加 rust/ 前缀以匹配 SonarCloud 的 sonar.sources
        if not fpath.startswith("rust/"):
            fpath = "rust/" + fpath
        lines = parse_cobertura_class(cls)
        if not lines:
            continue
        if fpath in files:
            for ln, cov in lines.items():
                files[fpath][ln] = files[fpath].get(ln, False) or cov
        else:
            files[fpath] = lines
    return files


def parse_sdk_coverage(path):
    """解析 AetherSDK llvm-cov cobertura XML（<class filename><lines><line hits>）。

    路径规范化为 Packages/AetherCore/Sources/AetherSDK/xxx.swift 格式。
    """
    files = {}
    try:
        root = ET.parse(path).getroot()
    except (ET.ParseError, FileNotFoundError):
        return files
    for cls in root.iter("class"):
        fpath = cls.get("filename")
        if not fpath:
            continue
        # llvm-cov 输出可能是绝对路径或相对路径，规范化为 Packages/AetherCore/... 格式
        if "Sources/AetherSDK/" in fpath:
            idx = fpath.find("Sources/AetherSDK/")
            if idx > 0 and not fpath.startswith("Packages/"):
                fpath = "Packages/AetherCore/" + fpath[idx:]
        elif not fpath.startswith("Packages/"):
            continue
        lines = parse_cobertura_class(cls)
        if not lines:
            continue
        if fpath in files:
            for ln, cov in lines.items():
                files[fpath][ln] = files[fpath].get(ln, False) or cov
        else:
            files[fpath] = lines
    return files


def merge_files(sources):
    """合并多源覆盖率：union 策略，任一源覆盖即视为覆盖。

    sources: list of {filepath: {lineno: covered_bool}}
    返回 (merged_files, total_covered, total_lines)
    """
    all_paths = set()
    for s in sources:
        all_paths.update(s.keys())

    merged_files = {}
    total_covered = 0
    total_lines = 0
    for path in all_paths:
        merged_lines = {}
        for s in sources:
            for ln, cov in s.get(path, {}).items():
                merged_lines[ln] = merged_lines.get(ln, False) or cov
        merged_files[path] = merged_lines
        total_covered += sum(1 for c in merged_lines.values() if c)
        total_lines += len(merged_lines)
    return merged_files, total_covered, total_lines


def write_merged_xml(output_path, merged_files):
    """写入合并后的 cobertura XML。"""
    with open(output_path, 'w', encoding='utf-8') as f:
        f.write('<coverage version="1">\n')
        for path in sorted(merged_files.keys()):
            lines = merged_files[path]
            f.write(f'  <file path="{path}">\n')
            for ln in sorted(lines.keys()):
                covered = "true" if lines[ln] else "false"
                f.write(f'    <lineToCover lineNumber="{ln}" covered="{covered}"/>\n')
            f.write(f'  </file>\n')
        f.write('</coverage>\n')


def main():
    if len(sys.argv) < 6:
        print(
            "Usage: merge-coverage.py <ios.xml> <macos.xml> <rust.xml> <sdk.xml> <output.xml>",
            file=sys.stderr,
        )
        sys.exit(1)

    ios_path, macos_path, rust_path, sdk_path, output_path = sys.argv[1:6]

    ios = parse_swift_coverage(ios_path)
    macos = parse_swift_coverage(macos_path)
    rust = parse_rust_coverage(rust_path)
    sdk = parse_sdk_coverage(sdk_path)

    merged_files, total_covered, total_lines = merge_files([ios, macos, rust, sdk])
    write_merged_xml(output_path, merged_files)

    rate = total_covered / total_lines if total_lines else 0
    print(f"Merged coverage: line-rate={rate:.4f} ({total_covered}/{total_lines} lines)")
    print(
        f"Files: iOS={len(ios)}, macOS={len(macos)}, Rust={len(rust)}, "
        f"AetherSDK={len(sdk)}, merged={len(merged_files)}"
    )


if __name__ == "__main__":
    main()
