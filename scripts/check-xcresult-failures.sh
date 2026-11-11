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
# 修好一条就从基线删一条，新写的坏用例则当场拦住。条目粒度从紧到松：
#   `Class/method` 精确 · `Class/testFoo*` 同族豁免 · `Class/*~crash|*~timeout` 形态豁免 · `Class/*` 整类豁免
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
import fnmatch, json, os, sys

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
known_patterns = []
known_shape_patterns = []
# 崩溃与超时的责任用例是 xcresult "归因"出来的：segv 或被杀落在当时正在跑的那条方法上，
# 每轮可以完全不同（UI 四轮里超时受害者换了 5 个方法），按方法锚定永远追不完。
# `*~<shape>` 条目只豁免该形态，同一个类里新增的断言失败和其它形态照旧拦。
CRASH_MARKS = ('crashed with signal', 'segv', 'crash:', 'fatal error')
SHAPES = {
    'crash': CRASH_MARKS,
    'timeout': ('exceeded execution time allowance',),
}


def shape_of(text):
    low = (text or '').lower()
    for name, marks in SHAPES.items():
        if any(m in low for m in marks):
            return name
    return None


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
            shape = None
            for name in SHAPES:
                suffix = '~' + name
                if tid.endswith(suffix):
                    tid = tid[:-len(suffix)]
                    shape = name
                    break
            if '*' in tid:
                if shape:
                    known_shape_patterns.append((tid, shape))
                else:
                    known_patterns.append(tid)
            elif tid:
                known_exact.add(tid)
    if known_shape_patterns:
        shape_counts = {}
        for _, shape_name in known_shape_patterns:
            shape_counts[shape_name] = shape_counts.get(shape_name, 0) + 1
        print('shape-only exemptions for %s: %s' % (
            label, ', '.join('%s=%d' % (k, v) for k, v in sorted(shape_counts.items()))))
else:
    print('NOTE: baseline %s not found; treating every failure as new' % baseline_path)


def classify(tid, text):
    """返回 (是否在基线内, 靠哪种形态豁免或 None)。逐条 occurrence 判定：同一条用例
    在一轮里既崩溃又断言失败时，断言那次仍算基线外。"""
    if tid in known_exact:
        return True, None
    if any(fnmatch.fnmatchcase(tid, pat) for pat in known_patterns):
        return True, None
    shape = shape_of(text)
    if shape and any(fnmatch.fnmatchcase(tid, pat) and name == shape
                     for pat, name in known_shape_patterns):
        return True, shape
    return False, None


new, known_hits, shape_exempt = [], [], []
for tid, text in entries:
    known, via_shape = classify(tid, text)
    (known_hits if known else new).append((tid, text))
    if via_shape:
        shape_exempt.append((tid, text, via_shape))

print('result=%s passed=%s failed=%s skipped=%s | baseline(%s)=%d exact + %d pattern + %d shape-only'
      % (data.get('result'), data.get('passedTests'), failed_count,
         data.get('skippedTests'), label, len(known_exact), len(known_patterns),
         len(known_shape_patterns)))

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
if shape_exempt:
    print('  其中 %d 条属形态豁免（崩溃/超时的责任用例每轮轮换，务必回看原始日志）：'
          % len(shape_exempt))
    for tid, reason, shape_name in shape_exempt[:20]:
        print('    %s-exempt: %s :: %s' % (shape_name, tid, reason))
for tid, reason in known_hits[:10]:
    print('  known: %s :: %s' % (tid, reason))
if len(known_hits) > 10:
    print('  ... 其余 %d 条见 %s' % (len(known_hits) - 10, baseline_path))
summary_lines = ['## %s 测试：%d 个失败均在基线内（历史债）' % (label, len(known_hits)), '']
if shape_exempt:
    summary_lines.append('本轮形态豁免 %d 条（`*~crash` / `*~timeout` 条目只豁免该形态的归因，断言失败照旧拦）：'
                         % len(shape_exempt))
    summary_lines += ['- `%s`（%s 形态）— %s' % (t, s, r.replace('|', '\\|'))
                      for t, r, s in shape_exempt[:20]]
    summary_lines.append('')
summary_lines += ['- `%s`' % t for t, _ in known_hits[:200]]
emit_section(summary_lines)
sys.exit(0)
PY
