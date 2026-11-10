#!/bin/bash
# CI 模拟器设置脚本 - 确保目标 iPhone 模拟器可用（默认 iPhone 17，可用 IOS_SIMULATOR_NAME 覆盖，如 iPhone Duo）
# M-C7: 添加 DEVTYPE/RUNTIME 空值校验，避免 simctl create 在参数为空时
#       报出难以理解的错误（如 "No device type with name ''"）。
set -e

# 模拟器名称可通过环境变量覆盖（默认 iPhone 17，与 ci.yml env.IOS_SIMULATOR_NAME 对齐）
SIMULATOR_NAME="${IOS_SIMULATOR_NAME:-iPhone 17}"

# 精确匹配 "${name} ("，避免 "iPhone 17" 误匹配 "iPhone 17 Pro"
if xcrun simctl list devices available | grep -q "${SIMULATOR_NAME} ("; then
  echo "$SIMULATOR_NAME simulator already exists"
  xcrun simctl list devices available | grep iPhone
  exit 0
fi

# 获取 iPhone 设备类型（优先目标名称，依次回退；iPhone Duo 为折叠屏新设备）
DEVTYPE=$(xcrun simctl list devicetypes -j | python3 -c "
import json, sys
data = json.load(sys.stdin)
# 回退顺序：目标设备 → iPhone 17 → iPhone Duo → 16 Pro → 16 → 15 Pro → 15 → 14 Pro
for name in ['$SIMULATOR_NAME', 'iPhone 17', 'iPhone Duo', 'iPhone 16 Pro', 'iPhone 16', 'iPhone 15 Pro', 'iPhone 15', 'iPhone 14 Pro']:
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

# 获取支持该设备类型的最新 iOS runtime。
# iPhone Duo 需要专用 runtime（如 iOS-27-2-iPhone19-4），通用 iOS runtime 不支持它，
# 因此必须按 supportedDeviceTypes 过滤，不能盲目取最新 runtime。
find_runtime() {
  xcrun simctl list runtimes -j | python3 -c "
import json, sys
data = json.load(sys.stdin)
devtype = '$DEVTYPE'
for r in data['runtimes']:
    if 'iOS' not in r['name'] or not r['isAvailable']:
        continue
    if any(t['identifier'] == devtype for t in r.get('supportedDeviceTypes', [])):
        print(r['identifier'])
" | tail -1
}

RUNTIME=$(find_runtime)

# CI runner 可能未预装目标设备的专用 runtime（如 iPhone Duo），下载后重试一次
if [ -z "$RUNTIME" ]; then
  echo "No installed iOS runtime supports $DEVTYPE; downloading iOS platform runtime..."
  xcodebuild -downloadPlatform iOS
  RUNTIME=$(find_runtime)
fi

if [ -z "$RUNTIME" ]; then
  echo "ERROR: No available iOS runtime supports device type $DEVTYPE (even after download)"
  echo "Available runtimes:"
  xcrun simctl list runtimes
  exit 1
fi

echo "Creating $SIMULATOR_NAME simulator with device type: $DEVTYPE, runtime: $RUNTIME"
xcrun simctl create "$SIMULATOR_NAME" "$DEVTYPE" "$RUNTIME"
xcrun simctl list devices available | grep iPhone