#!/bin/bash
set -uo pipefail
# 用法: scripts/check-xcresult-failures.sh <path.xcresult> [label] [baseline-file]
#
# xcodebuild 非零退出并不等于用例失败：测试进程崩溃重启、模拟器不稳定都会让它在
# 已执行用例全部通过的情况下退出非零。本脚本区分三种情形：
#   1. 没有失败用例            → 容忍放行（退出 0）
#   2. 失败用例全部在基线内    → 警告放行（退出 0），并把清单写进 step summary
#   3. 出现基线外的新增失败    → 阻断（退出 1）
# 基线（默认 scripts/known-test-failures.txt）用于锚定既有的历史失败债务：
# 修好一条就从基线删一条，新写的坏用例则当场拦住。
#
# 注意 xcresulttool 的 JSON summary 里没有 "failed" 这个键（实际字段是 failedTests /
# result / testFailures[]，失败项含 testName / testIdentifierString / failureText），
# 因此不能用 grep 计数失败行。

BUNDLE="${1:-}"
LABEL="${2:-test}"
BASELINE="${3:-scripts/known-test-failures.txt}"

if [ -z "$BUNDLE" ]; then
  echo "usage: $0 <path.xcresult> [label] [baseline-file]" >&2
  exit 2
fi

if [ ! -e "$BUNDLE" ]; then
  echo "ERROR: no $LABEL results generated ($BUNDLE missing)" >&2
  exit 1
fi

SUMMARY_FILE=$(mktemp)
trap 'rm -f "$SUMMARY_FILE"' EXIT
xcrun xcresulttool get test-results summary --path "$BUNDLE" > "$SUMMARY_FILE" 2>/dev/null || true

if [ ! -s "$SUMMARY_FILE" ]; then
  # 包损坏或未写完时无法判定，宁可报错也不要静默放行真实失败
  echo "ERROR: cannot read test summary from $BUNDLE (corrupt or incomplete bundle)" >&2
  exit 1
fi

python3 - "$LABEL" "$BASELINE" "$SUMMARY_FILE" <<'PY'
import json, os, sys

label, baseline_path, summary_path = sys.argv[1:4]

with open(summary_path, encoding='utf-8', errors='replace') as fh:
    data = json.load(fh)

failures = data.get('testFailures') or []
entries = []
for f in failures:
    tid = (f.get('testIdentifierString') or f.get('testName') or '').strip()
    if tid.endswith('()'):
        tid = tid[:-2]
    entries.append((tid, (f.get('failureText') or '').strip()))

failed_count = data.get('failedTests')
if failed_count is None:
    failed_count = len(entries)

known_exact = set()
known_class = set()
if os.path.exists(baseline_path):
    with open(baseline_path, encoding='utf-8') as fh:
        for line in fh:
            line = line.strip()
            if not line or line.startswith('#') or ':' not in line:
                continue
            scope, _, tid = line.partition(':')
            if scope.strip() != label:
                continue
            tid = tid.strip()
            # xcresult 的 id 不含括号，手写基线常带 Swift 的 method() 风格，统一掉
            if tid.endswith('()'):
                tid = tid[:-2]
            if tid.endswith('/*'):
                known_class.add(tid[:-2])
            elif tid:
                known_exact.add(tid)
else:
    print('NOTE: baseline %s not found; treating every failure as new' % baseline_path)


def is_known(tid):
    """条目支持两种粒度：`Class/method` 精确匹配，`Class/*` 整类豁免。
    超时类失败的受害用例每次不同（同一批里换个方法触发），只能按类锚定。"""
    if tid in known_exact:
        return True
    return tid.split('/', 1)[0] in known_class


new = [(t, r) for (t, r) in entries if not is_known(t)]
known_hits = [(t, r) for (t, r) in entries if is_known(t)]

print('result=%s passed=%s failed=%s skipped=%s | baseline(%s)=%d exact + %d class'
      % (data.get('result'), data.get('passedTests'), failed_count,
         data.get('skippedTests'), label, len(known_exact), len(known_class)))

# 计数多于可枚举明细时，差额无法核对基线，按新增处理
if failed_count > len(entries):
    new.append(('(未列明细的失败 %d 个)' % (failed_count - len(entries)), ''))


def emit_section(lines):
    path = os.environ.get('GITHUB_STEP_SUMMARY')
    if not path:
        return
    with open(path, 'a', encoding='utf-8') as fh:
        fh.write('\n'.join(lines) + '\n')


if not entries and failed_count == 0:
    print('all %s tests passed (xcodebuild exited non-zero: simulator/host instability)' % label)
    sys.exit(0)

if new:
    print('ERROR: %d new %s failure(s) outside the baseline:' % (len(new), label))
    for tid, reason in new[:200]:
        print('  NEW FAILURE: %s :: %s' % (tid, reason))
    if known_hits:
        print('  (+%d baseline-known %s failure(s))' % (len(known_hits), label))
    emit_section(['## %s 测试：出现基线外的新增失败' % label, '']
                 + ['- `%s` — %s' % (t, r.replace('|', '\\|')) for t, r in new[:200]])
    sys.exit(1)

print('WARNING: %d %s failure(s) are all baseline-known; no new failures' % (len(known_hits), label))
for tid, reason in known_hits[:10]:
    print('  known: %s :: %s' % (tid, reason))
if len(known_hits) > 10:
    print('  ... 其余 %d 条见 %s' % (len(known_hits) - 10, baseline_path))
emit_section(['## %s 测试：%d 个失败均在基线内（历史债）' % (label, len(known_hits)), '']
             + ['- `%s`' % t for t, _ in known_hits[:200]])
sys.exit(0)
PY
