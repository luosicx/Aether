#!/usr/bin/env bash
# 构建 aether_core.xcframework 并生成 C 头，供 SPM binaryTarget 消费。
# 仅在 macOS 上运行（需 xcodebuild）。CI 中由 rust-apple job 调用。
set -euo pipefail
cd "$(dirname "$0")/.."

# onig_sys 的 C 代码由 cc crate 用 clang 编译，未显式指定时 minos 取宿主 OS 版本，
# 链接进 deployment target 更低的 App 会报「built for newer macOS version」告警。
# 与 Xcode 工程 / Package.swift 的部署目标保持一致。
export MACOSX_DEPLOYMENT_TARGET=14.0
export IPHONEOS_DEPLOYMENT_TARGET=17.0

OUT="aether_core.xcframework"
rm -rf "$OUT"
mkdir -p build

TARGETS=(
  "aarch64-apple-ios"
  "aarch64-apple-ios-sim"
  "x86_64-apple-ios"
  "aarch64-apple-darwin"
  "x86_64-apple-darwin"
)

for t in "${TARGETS[@]}"; do
  echo "==> building $t"
  cargo build -p aether-core-ffi --release --target "$t"
  lib="target/$t/release/libaether_core_ffi.a"
  mkdir -p "build/$t"
  cp "$lib" "build/$t/"
done

ARGS=()
for t in "${TARGETS[@]}"; do
  ARGS+=(-library "build/$t/libaether_core_ffi.a")
done

xcodebuild -create-xcframework \
  "${ARGS[@]}" \
  -output "$OUT"

# 生成 C 头
cbindgen --crate aether-core-ffi -o "build/aether_core_ffi.h" --config aether-core-ffi/cbindgen.toml

echo "==> 产出: $OUT, build/aether_core_ffi.h"
