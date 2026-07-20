#!/bin/bash
# CI 模拟器设置脚本 - 确保 iPhone 17 模拟器可用
# M-C7: 添加 DEVTYPE/RUNTIME 空值校验，避免 simctl create 在参数为空时
#       报出难以理解的错误（如 "No device type with name ''"）。
set -e

# 模拟器名称可通过环境变量覆盖（默认 iPhone 17，与 ci.yml env.IOS_SIMULATOR_NAME 对齐）
SIMULATOR_NAME="${IOS_SIMULATOR_NAME:-iPhone 17}"

if xcrun simctl list devices available | grep -q "$SIMULATOR_NAME"; then
  echo "$SIMULATOR_NAME simulator already exists"
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

if [ -z "$RUNTIME" ]; then
  echo "ERROR: No available iOS runtime found"
  echo "Available runtimes:"
  xcrun simctl list runtimes
  exit 1
fi

# 获取 iPhone 设备类型（优先 iPhone 17，依次回退到旧型号）
DEVTYPE=$(xcrun simctl list devicetypes -j | python3 -c "
import json, sys
data = json.load(sys.stdin)
# 回退顺序：iPhone 17 → 16 Pro → 16 → 15 Pro → 15 → 14 Pro
for name in ['$SIMULATOR_NAME', 'iPhone 16 Pro', 'iPhone 16', 'iPhone 15 Pro', 'iPhone 15', 'iPhone 14 Pro']:
    for d in data['devicetypes']:
        if d['name'] == name:
            print(d['identifier'])
            sys.exit(0)
")

if [ -z "$DEVTYPE" ]; then
  echo "ERROR: No suitable iPhone device type found"
  echo "Available devicetypes:"
  xcrun simctl list devicetypes | grep iPhone
  exit 1
fi

echo "Creating $SIMULATOR_NAME simulator with device type: $DEVTYPE, runtime: $RUNTIME"
xcrun simctl create "$SIMULATOR_NAME" "$DEVTYPE" "$RUNTIME"
xcrun simctl list devices available | grep iPhone