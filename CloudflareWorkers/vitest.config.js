import { defineConfig } from "vitest/config";

// vitest 配置
// 默认 include 仅匹配 *.test.js / *.spec.js；此处显式纳入 stress-test.js
// （并发限流压测，无 .test. 后缀），使 npm run test:e2e 能覆盖到它。
export default defineConfig({
  test: {
    include: ["test/**/*.{test,spec}.js", "test/stress-test.js"],
  },
});
