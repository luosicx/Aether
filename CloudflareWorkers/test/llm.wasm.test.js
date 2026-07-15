import { describe, it, expect, beforeAll } from "vitest";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { initSync, SseState } from "../wasm/aether_sse.js";

describe("WASM SSE parser", () => {
  let state;
  beforeAll(() => {
    // Node/vitest 环境无 fetch 本地文件能力，改用 initSync 同步加载 wasm 二进制。
    // 生产环境（Workers）仍走 default export (init)，由 fetch 完成异步加载。
    const wasmPath = fileURLToPath(new URL("../wasm/aether_sse_bg.wasm", import.meta.url));
    const wasmBuffer = readFileSync(wasmPath);
    initSync({ module: wasmBuffer });
    state = new SseState();
  });

  it("extracts content", () => {
    const line = `data: {"choices":[{"delta":{"content":"Hi"}}]}`;
    expect(state.extractContent(line)).toBe("Hi");
  });

  it("returns null for [DONE]", () => {
    // wasm-bindgen 将 Option::None 映射为 undefined（非 null）
    expect(state.extractContent("data: [DONE]")).toBeFalsy();
  });

  it("returns null for non-data lines", () => {
    expect(state.extractContent(": keepalive")).toBeFalsy();
    expect(state.extractContent("event: ping")).toBeFalsy();
  });

  it("returns null for empty content", () => {
    const line = `data: {"choices":[{"delta":{"content":""}}]}`;
    expect(state.extractContent(line)).toBeFalsy();
  });

  it("returns null for malformed JSON", () => {
    expect(state.extractContent("data: {not json")).toBeFalsy();
  });

  it("accumulates tool calls across chunks", () => {
    const s = new SseState();
    const first = `data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"c1","type":"function","function":{"name":"get_weather","arguments":""}}]}}]}`;
    s.parseWithTools(first);
    const second = `data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\\"city\\":\\"BJ\\"}"}}]}}]}`;
    const r = JSON.parse(s.parseWithTools(second));
    expect(r.toolCalls[0].arguments).toBe('{"city":"BJ"}');
    expect(r.toolCalls[0].name).toBe("get_weather");
    expect(r.toolCalls[0].type).toBe("function");
  });
});
