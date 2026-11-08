#!/usr/bin/env python3
"""从 xcodebuild 日志提取每个测试类的实际耗时，供 CI 分片加权使用。

用法:
    python3 scripts/extract-macos-test-durations.py <日志...> -o .github/macos-test-durations.json

取数方式是把每条日志行的时间差归属到最近一个 "Test Suite '<类名>' started" 的类。
这样能覆盖被 -maximum-test-execution-time-allowance 杀掉的挂起用例（它们不会有
"Test Suite ... passed" 行），而正是这些挂起造成了分片间耗时失衡。

注意：数据来自某次 CI 运行的快照，测试增减后未覆盖的类会退化为中位单测耗时估算，
必要时重新跑一遍提取。
"""

from __future__ import annotations

import argparse
import json
import re
import sys

TS = re.compile(r"^\d{4}-\d\d-\d\dT(\d\d:\d\d:\d\d\.\d+)Z ")
SUITE_START = re.compile(r"^Test Suite '([^']+)' started at ")
SUITE_END = re.compile(r"^Test Suite '([^']+)' (?:passed|failed) at ")


def seconds(clock: str) -> float:
    hours, minutes, secs = clock.split(":")
    return int(hours) * 3600 + int(minutes) * 60 + float(secs)


def extract(paths: list[str]) -> dict[str, float]:
    durations: dict[str, float] = {}
    for path in paths:
        current: str | None = None
        previous: float | None = None
        with open(path, encoding="utf-8", errors="replace") as handle:
            for line in handle:
                stamp = TS.match(line)
                if not stamp:
                    continue
                now = seconds(stamp.group(1))
                if previous is not None and current:
                    durations[current] = durations.get(current, 0.0) + (now - previous)
                previous = now

                body = line[stamp.end():]
                started = SUITE_START.match(body)
                if started:
                    name = started.group(1)
                    # 过滤 'Selected tests'、'AetherTests.xctest' 等容器套件
                    current = name if name.endswith("Tests") and name != "Selected tests" else None
                    continue
                if SUITE_END.match(body):
                    current = None
    return {name: round(value, 1) for name, value in sorted(durations.items())}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("logs", nargs="+", help="xcodebuild 日志（可传多个分片）")
    parser.add_argument("-o", "--output", required=True, help="输出的 JSON 路径")
    args = parser.parse_args()

    durations = extract(args.logs)
    if not durations:
        print("未从日志中解析到任何测试套件耗时", file=sys.stderr)
        return 1
    with open(args.output, "w", encoding="utf-8") as handle:
        json.dump(durations, handle, indent=2, ensure_ascii=False)
        handle.write("\n")
    total = sum(durations.values())
    print(f"{len(durations)} 个测试类，合计 {total / 60:.1f} 分钟 -> {args.output}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
