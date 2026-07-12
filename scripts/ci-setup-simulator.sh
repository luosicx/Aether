#!/bin/bash
# CI 模拟器设置脚本 - 确保 iPhone 17 模拟器可用
set -e

if xcrun simctl list devices available | grep -q "iPhone 17"; then
  echo "iPhone 17 simulator already exists"
  xcrun simctl list devices available | grep iPhone
  exit 0
fi

# 获取最新 iOS runtime
RUNTIME=$(xcrun simctl list runtimes -j | python3 -c "
import json, sys
data = json.load(sys.stdin)
for r in data['runtimes']:
    if 'iOS' in r['name'] and r['isAvailable']:
        print(r['identifier'])
" | tail -1)

# 获取 iPhone 设备类型（优先 iPhone 17，依次回退）
DEVTYPE=$(xcrun simctl list devicetypes -j | python3 -c "
import json, sys
data = json.load(sys.stdin)
for name in ['iPhone 17', 'iPhone 16 Pro', 'iPhone 16', 'iPhone 15 Pro', 'iPhone 15']:
    for d in data['devicetypes']:
        if d['name'] == name:
            print(d['identifier'])
            sys.exit(0)
")

echo "Creating iPhone 17 simulator with device type: $DEVTYPE, runtime: $RUNTIME"
xcrun simctl create "iPhone 17" "$DEVTYPE" "$RUNTIME"
xcrun simctl list devices available | grep iPhone