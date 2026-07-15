import { describe, it, expect, beforeAll } from "vitest";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { initSync, TokenCounter } from "../wasm/aether_sse.js";

describe("WASM TokenCounter", () => {
  beforeAll(() => {
    const wasmPath = fileURLToPath(new URL("../wasm/aether_sse_bg.wasm", import.meta.url));
    const wasmBuffer = readFileSync(wasmPath);
    initSync({ module: wasmBuffer });
  });

  // 测试期望与 Swift `StringTokenCountTests.swift` 表驱动用例完全一致，
  // 确保 Rust WASM 实现与 Apple 端 Swift 实现输出相同（可互换）。

  it("empty string returns 0", () => {
    expect(TokenCounter.estimateTokens("")).toBe(0);
  });

  it("single english word: Int(1.3) = 1", () => {
    expect(TokenCounter.estimateTokens("hello")).toBe(1);
  });

  it("two english words: Int(2.6) = 2", () => {
    expect(TokenCounter.estimateTokens("hello world")).toBe(2);
  });

  it("consecutive spaces collapsed: 2 words", () => {
    expect(TokenCounter.estimateTokens("hello  world")).toBe(2);
  });

  it("pure chinese: 1 word + 4 non-ascii = 7", () => {
    expect(TokenCounter.estimateTokens("你好世界")).toBe(7);
  });

  it("four english words: Int(4*1.3=5.2) = 5", () => {
    expect(TokenCounter.estimateTokens("hello world foo bar")).toBe(5);
  });

  it("mixed chinese english: 2 words + 2 non-ascii = 5", () => {
    expect(TokenCounter.estimateTokens("hello 你好")).toBe(5);
  });
});
