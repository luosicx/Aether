#!/usr/bin/env python3
"""将 AetherTests 下的测试类按测试方法数均衡分片。

用法: python3 ci-shard-tests.py <shard_index> <total_shards>
输出: 当前分片包含的测试类名（每行一个），供 xcodebuild -only-testing 使用

分片策略：按测试方法数降序排序，贪心分配到当前负载最小的分片（LPT 调度），
保证各分片测试方法数大致均衡。新加测试类自动分配，无需手动维护分片列表。
"""
import sys
import os
import re
import glob


def collect_test_classes():
    """收集所有测试类名及其测试方法数。

    排除整个类被 #if os(macOS) 包裹的测试类（在 iOS Simulator 上不存在，
    -only-testing 会报错）。仅部分方法被 #if os(macOS) 包裹的类保留（iOS 上
    运行非 macOS 方法）。
    """
    test_classes = []
    for f in sorted(glob.glob("AetherTests/*.swift")):
        with open(f) as fh:
            content = fh.read()
        m = re.search(r'class\s+(\w+)\s*:\s*XCTestCase', content)
        if not m:
            continue
        name = m.group(1)
        # 判断是否整个类被 #if os(macOS) 包裹：
        # #if os(macOS) 出现在 class 声明之前
        first_if = re.search(r'#if\s+os\(macOS\)', content)
        class_match = re.search(r'class\s+\w+\s*:\s*XCTestCase', content)
        if first_if and class_match and first_if.start() < class_match.start():
            # 整个类被 #if os(macOS) 包裹，跳过（macOS-only）
            continue
        count = len(re.findall(r'func\s+test\w+', content))
        test_classes.append((name, count))
    return test_classes


def shard_classes(test_classes, total_shards):
    """LPT 调度：按测试方法数降序排序，贪心分配到负载最小的分片。"""
    test_classes.sort(key=lambda x: -x[1])
    shards = [[] for _ in range(total_shards)]
    loads = [0] * total_shards
    for name, count in test_classes:
        min_shard = loads.index(min(loads))
        shards[min_shard].append(name)
        loads[min_shard] += count
    return shards, loads


def main():
    if len(sys.argv) != 3:
        print("用法: python3 ci-shard-tests.py <shard_index> <total_shards>",
              file=sys.stderr)
        sys.exit(1)

    shard_index = int(sys.argv[1])
    total_shards = int(sys.argv[2])

    if shard_index < 0 or shard_index >= total_shards:
        print(f"错误: shard_index {shard_index} 超出范围 [0, {total_shards})",
              file=sys.stderr)
        sys.exit(1)

    test_classes = collect_test_classes()
    if not test_classes:
        print("错误: 未找到测试类", file=sys.stderr)
        sys.exit(1)

    shards, loads = shard_classes(test_classes, total_shards)

    # 输出当前分片的测试类名
    for cls in shards[shard_index]:
        print(cls)

    # 调试信息输出到 stderr（不干扰 stdout）
    print(f"# 分片负载: {loads}", file=sys.stderr)
    print(f"# 分片 {shard_index}: {len(shards[shard_index])} 个测试类, "
          f"{loads[shard_index]} 个测试方法", file=sys.stderr)


if __name__ == "__main__":
    main()
