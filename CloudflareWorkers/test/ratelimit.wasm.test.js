import { describe, it, expect, beforeAll } from "vitest";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { initSync, RateLimiter } from "../wasm/aether_sse.js";

describe("WASM RateLimiter", () => {
  beforeAll(() => {
    const wasmPath = fileURLToPath(new URL("../wasm/aether_sse_bg.wasm", import.meta.url));
    const wasmBuffer = readFileSync(wasmPath);
    initSync({ module: wasmBuffer });
  });

  it("starts full and allows acquire within capacity", () => {
    const now = 1_000_000;
    const rl = new RateLimiter(5, 1, now); // capacity=5, 1/sec
    for (let i = 0; i < 5; i++) {
      expect(rl.acquire(1, now)).toBe(0);
    }
  });

  it("blocks when tokens exhausted", () => {
    const now = 1_000_000;
    const rl = new RateLimiter(3, 1, now);
    for (let i = 0; i < 3; i++) {
      rl.acquire(1, now);
    }
    const retry = rl.acquire(1, now);
    expect(retry).toBeGreaterThan(0);
  });

  it("refills tokens over time", () => {
    const now = 1_000_000;
    const rl = new RateLimiter(10, 10, now); // 10/sec
    // 耗尽
    for (let i = 0; i < 10; i++) {
      rl.acquire(1, now);
    }
    // 1 秒后补充 10 个
    expect(rl.acquire(1, now + 1000)).toBe(0);
  });

  it("refill capped at capacity", () => {
    const now = 1_000_000;
    const rl = new RateLimiter(10, 100, now); // 100/sec, cap 10
    rl.acquire(5, now);
    // 10 秒后应补充 1000 但 cap 在 10
    expect(rl.availableTokens(now + 10_000)).toBe(10);
  });

  it("retry after estimates wait time", () => {
    const now = 1_000_000;
    const rl = new RateLimiter(5, 2, now); // 2/sec
    for (let i = 0; i < 5; i++) {
      rl.acquire(1, now);
    }
    const retry = rl.acquire(1, now);
    // deficit=1, rate=2 → 0.5 → ceil → 1
    expect(retry).toBe(1);
  });

  it("zero capacity immediately blocks", () => {
    const now = 1_000_000;
    const rl = new RateLimiter(0, 1, now);
    expect(rl.acquire(1, now)).toBeGreaterThan(0);
  });

  it("zero n always succeeds", () => {
    const now = 1_000_000;
    const rl = new RateLimiter(0, 0, now);
    expect(rl.acquire(0, now)).toBe(0);
  });

  it("zero refill rate never replenishes", () => {
    const now = 1_000_000;
    const rl = new RateLimiter(2, 0, now);
    rl.acquire(2, now);
    expect(rl.acquire(1, now + 999_999)).toBeGreaterThan(0);
  });

  it("partial refill allows partial acquire", () => {
    const now = 1_000_000;
    const rl = new RateLimiter(10, 10, now); // 10/sec
    for (let i = 0; i < 10; i++) {
      rl.acquire(1, now);
    }
    // 0.5 秒后补充 5 个
    expect(rl.acquire(5, now + 500)).toBe(0);
    // 再要 1 个失败
    expect(rl.acquire(1, now + 500)).toBeGreaterThan(0);
  });

  it("reset refills to capacity", () => {
    const now = 1_000_000;
    const rl = new RateLimiter(10, 1, now);
    for (let i = 0; i < 10; i++) {
      rl.acquire(1, now);
    }
    rl.reset(now + 5000);
    expect(rl.availableTokens(now + 5000)).toBe(10);
  });

  it("backward time does not refill", () => {
    const now = 1_000_000;
    const rl = new RateLimiter(10, 100, now);
    rl.acquire(5, now);
    // 时间倒退
    expect(rl.availableTokens(now - 1000)).toBe(5);
  });

  it("multiple acquires track correctly", () => {
    const now = 1_000_000;
    const rl = new RateLimiter(3, 3, now); // 3/sec
    expect(rl.acquire(1, now)).toBe(0);
    expect(rl.acquire(1, now)).toBe(0);
    expect(rl.acquire(1, now)).toBe(0);
    expect(rl.acquire(1, now)).toBeGreaterThan(0);
    // 1 秒后补满
    expect(rl.acquire(3, now + 1000)).toBe(0);
  });
});
