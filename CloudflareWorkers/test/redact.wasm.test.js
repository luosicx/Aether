import { describe, it, expect, beforeAll } from "vitest";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { initSync, Redactor } from "../wasm/aether_sse.js";

describe("WASM Redactor", () => {
  beforeAll(() => {
    const wasmPath = fileURLToPath(new URL("../wasm/aether_sse_bg.wasm", import.meta.url));
    const wasmBuffer = readFileSync(wasmPath);
    initSync({ module: wasmBuffer });
  });

  it("redacts UUID", () => {
    const input = "请求 ID: 550e8400-e29b-41d4-a716-446655440000 失败";
    expect(Redactor.redact(input)).toBe("请求 ID: [REDACTED_UUID] 失败");
  });

  it("redacts email", () => {
    const input = "联系 user@example.com 获取详情";
    expect(Redactor.redact(input)).toBe("联系 [REDACTED_EMAIL] 获取详情");
  });

  it("redacts URL", () => {
    const input = "访问 https://api.example.com/v1/chat 获取数据";
    expect(Redactor.redact(input)).toBe("访问 [REDACTED_URL] 获取数据");
  });

  it("redacts OpenAI token", () => {
    const input = "使用 sk-abc123xyz456 调用 API";
    expect(Redactor.redact(input)).toBe("使用 [REDACTED_TOKEN] 调用 API");
  });

  it("redacts Bearer token", () => {
    const input = "Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.token";
    expect(Redactor.redact(input)).toBe("Authorization: [REDACTED_TOKEN]");
  });

  it("redacts credential field", () => {
    const input = "配置 password=secret123 后启动";
    expect(Redactor.redact(input)).toBe("配置 [REDACTED_CREDENTIAL] 后启动");
  });

  it("redacts credential field case insensitive", () => {
    const input = "API_KEY=mykey456";
    expect(Redactor.redact(input)).toBe("[REDACTED_CREDENTIAL]");
  });

  it("redacts path", () => {
    const input = "读取 /Users/alice/.ssh/id_rsa 失败";
    expect(Redactor.redact(input)).toBe("读取 [REDACTED_PATH] 失败");
  });

  it("does not redact plain message", () => {
    const input = "Network timeout: 连接超时";
    expect(Redactor.redact(input)).toBe("Network timeout: 连接超时");
  });

  it("redacts multiple patterns", () => {
    const input = "用户 user@test.com 访问 https://example.com，token: sk-abc123";
    const result = Redactor.redact(input);
    expect(result).toContain("[REDACTED_EMAIL]");
    expect(result).toContain("[REDACTED_URL]");
    expect(result).toContain("[REDACTED_TOKEN]");
    expect(result).not.toContain("user@test.com");
    expect(result).not.toContain("example.com");
    expect(result).not.toContain("sk-abc123");
  });

  it("empty string unchanged", () => {
    expect(Redactor.redact("")).toBe("");
  });

  it("URL not mistaken as path", () => {
    const input = "访问 https://example.com/path/to/resource";
    expect(Redactor.redact(input)).toBe("访问 [REDACTED_URL]");
  });
});
