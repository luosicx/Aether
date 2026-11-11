#!/bin/bash
set -uo pipefail
# 用法: scripts/check-xcresult-failures.sh <path.xcresult> [label]
#
# xcodebuild 非零退出并不等于用例失败：测试进程崩溃重启、模拟器不稳定都会让它在
# 已执行用例全部通过的情况下退出非零。本脚本区分两种情形，仅在真的有用例失败时退出 1。
#
# 注意 xcresulttool 的 JSON summary 里没有 "failed" 这个键（实际字段是 failedTests /
# result / testFailures[]，失败项含 testName / testIdentifierString / failureText），
# 因此不能用 grep 计数失败行。

BUNDLE="${1:-}"
LABEL="${2:-test}"

if [ -z "$BUNDLE" ]; then
  echo "usage: $0 <path.xcresult> [label]" >&2
  exit 2
fi

if [ ! -e "$BUNDLE" ]; then
  echo "ERROR: no $LABEL results generated ($BUNDLE missing)" >&2
  exit 1
fi

SUMMARY=$(xcrun xcresulttool get test-results summary --path "$BUNDLE" 2>/dev/null || true)
if [ -z "$SUMMARY" ]; then
  # 包损坏或未写完时无法判定，宁可报错也不要静默放行真实失败
  echo "ERROR: cannot read test summary from $BUNDLE (corrupt or incomplete bundle)" >&2
  exit 1
fi

if echo "$SUMMARY" | python3 -c '
import json, sys
d = json.load(sys.stdin)
failures = d.get("testFailures") or []
failed = d.get("failedTests")
if failed is None:
    failed = len(failures)
print("result=%s passed=%s failed=%s skipped=%s"
      % (d.get("result"), d.get("passedTests"), failed, d.get("skippedTests")))
for f in failures[:40]:
    print("FAILED: %s :: %s"
          % (f.get("testIdentifierString") or f.get("testName"), f.get("failureText") or ""))
sys.exit(0 if failed == 0 else 1)
'; then
  echo "all $LABEL tests passed (xcodebuild exited non-zero: simulator/host instability)"
else
  echo "ERROR: $LABEL test(s) failed" >&2
  exit 1
fi
