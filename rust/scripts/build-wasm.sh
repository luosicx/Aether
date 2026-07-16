#!/usr/bin/env bash
# 构建 aether-core-ffi 的 wasm-pack 产物，供 Cloudflare Workers 加载。
set -euo pipefail
cd "$(dirname "$0")/.."

# 使用绝对路径：wasm-pack 的 --out-dir 相对于 crate 目录解析，
# 而非 workspace 根目录，相对路径会落到错误位置。
OUT="$(cd .. && pwd)/CloudflareWorkers/wasm"
mkdir -p "$OUT"

wasm-pack build aether-core-ffi \
  --target web \
  --release \
  --out-dir "$OUT" \
  --out-name aether_sse

echo "==> 产出: $OUT/aether_sse.js, $OUT/aether_sse_bg.wasm"
