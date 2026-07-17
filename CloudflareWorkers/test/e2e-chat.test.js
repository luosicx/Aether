/**
 * Chat 路由端到端测试
 *
 * 通过 worker.fetch 完整走 鉴权 → 限流 → handleChatStream → SSE 输出 链路。
 * 依赖 WASM 的部分（callLLMStream 的 SSE 解析、redact 脱敏、checkRateLimit 令牌桶）
 * 用 vi.mock 替换为纯 JS 实现，使测试可在无 WASM 产物的纯 Node 环境运行；
 * KV（bff_tokens）与上游 LLM API 均用 Mock，不依赖真实 Cloudflare / 上游服务。
 */

import { describe, it, expect, beforeEach, vi } from "vitest";

// vi.hoisted：保证可变状态在 vi.mock 工厂执行时已就绪（vi.mock 会被提升到文件顶部）
const mocks = vi.hoisted(() => ({
  // 默认 LLM 流式实现：依次产出 3 个增量片段
  llmStream: async function* () {
    yield "你";
    yield "好";
    yield "！";
  },
  // 默认限流结果：放行
  rateLimit: { allowed: true, remaining: 59 },
}));

// 模拟 llm.js：仅替换 callLLMStream（WASM SSE 解析），其余导出保持原实现
vi.mock("../src/lib/llm.js", async (importActual) => {
  const actual = await importActual();
  return {
    ...actual,
    callLLMStream: async function* (...args) {
      yield* mocks.llmStream(...args);
    },
  };
});

// 模拟 redact.js：避免依赖 WASM Redactor（错误路径才用到）
vi.mock("../src/lib/redact.js", () => ({
  redact: async (s) => (s == null ? "" : String(s)),
}));

// 模拟 ratelimit.js：仅替换 checkRateLimit（WASM 令牌桶），rateLimitResponse 保持原实现
vi.mock("../src/lib/ratelimit.js", async (importActual) => {
  const actual = await importActual();
  return {
    ...actual,
    checkRateLimit: async () => mocks.rateLimit,
  };
});

// 在 vi.mock 之后导入 worker，确保其依赖被替换
import worker from "../worker.js";

// ============ 测试基础设施 ============

const VALID_TOKEN = "bff-token-valid";
const USER_ID = "user-chat-1";

/** 构造 KV mock：内存 Map，模拟 bff_tokens 命名空间 */
function makeKV() {
  const store = new Map();
  // 写入一条合法 token，值为 JSON 用户元数据
  store.set(VALID_TOKEN, JSON.stringify({ userId: USER_ID, name: "tester" }));
  return {
    get: async (key) => (store.has(key) ? store.get(key) : null),
    put: async (key, val) => {
      store.set(key, val);
    },
  };
}

/** 构造 env：仅 bff_tokens（chat 测试不依赖 DB 持久化） */
function makeEnv() {
  return {
    bff_tokens: makeKV(),
    DEEPSEEK_API_KEY: "mock-key",
    DEEPSEEK_BASE_URL: "https://deepseek.test",
    QWEN_API_KEY: "mock-key",
    QWEN_BASE_URL: "https://qwen.test",
  };
}

/** 构造 ctx：收集 waitUntil 后台任务，便于测试结束后 await 保证完成 */
function makeCtx() {
  const pending = [];
  return {
    waitUntil: (p) => {
      pending.push(Promise.resolve(p).catch(() => {}));
    },
    _pending: pending,
  };
}

/** 构造 Request */
function makeRequest(path, { method = "GET", token, body, headers = {} } = {}) {
  const h = new Headers(headers);
  if (token) h.set("X-BFF-Token", token);
  const init = { method, headers: h };
  if (body !== undefined) {
    init.body = typeof body === "string" ? body : JSON.stringify(body);
    if (!h.has("Content-Type")) h.set("Content-Type", "application/json");
  }
  return new Request("https://bff.test" + path, init);
}

/** 从 SSE 响应体中提取所有 data 行负载 */
function parseSSEData(text) {
  return text
    .split("\n\n")
    .map((blk) => {
      const line = blk.split("\n").find((l) => l.startsWith("data:"));
      return line ? line.slice(5).trim() : null;
    })
    .filter(Boolean);
}

beforeEach(() => {
  // 每个用例前重置默认行为
  mocks.llmStream = async function* () {
    yield "你";
    yield "好";
    yield "！";
  };
  mocks.rateLimit = { allowed: true, remaining: 59 };
});

// ============ 测试用例 ============

describe("E2E /chat/stream", () => {
  it("缺少 X-BFF-Token 返回 401", async () => {
    const env = makeEnv();
    const ctx = makeCtx();
    const req = makeRequest("/chat/stream", {
      method: "POST",
      body: { message: "hi" },
    });
    const resp = await worker.fetch(req, env, ctx);
    expect(resp.status).toBe(401);
    const data = await resp.json();
    expect(data.error).toMatch(/Token/i);
  });

  it("无效 X-BFF-Token 返回 401", async () => {
    const env = makeEnv();
    const ctx = makeCtx();
    const req = makeRequest("/chat/stream", {
      method: "POST",
      token: "token-not-in-kv",
      body: { message: "hi" },
    });
    const resp = await worker.fetch(req, env, ctx);
    expect(resp.status).toBe(401);
  });

  it("合法 token 流式响应：200 + SSE 格式正确（delta/done/[DONE]）", async () => {
    const env = makeEnv();
    const ctx = makeCtx();
    const req = makeRequest("/chat/stream", {
      method: "POST",
      token: VALID_TOKEN,
      body: { message: "你好" },
    });
    const resp = await worker.fetch(req, env, ctx);
    expect(resp.status).toBe(200);
    expect(resp.headers.get("Content-Type")).toContain("text/event-stream");

    const text = await resp.text();
    // 等待后台持久化任务（无 DB 仍会触发流式任务，确保关闭）
    await Promise.all(ctx._pending);

    const payloads = parseSSEData(text);
    // 应包含 3 个 delta + 1 个 done + [DONE]
    expect(payloads).toHaveLength(5);

    const deltas = payloads.slice(0, 3).map((p) => JSON.parse(p));
    expect(deltas.map((d) => d.type)).toEqual(["delta", "delta", "delta"]);
    expect(deltas.map((d) => d.content)).toEqual(["你", "好", "！"]);

    const done = JSON.parse(payloads[3]);
    expect(done.type).toBe("done");
    expect(done.conversationId).toBeTruthy();
    expect(done.messageId).toBeTruthy();
    expect(done.userMessageId).toBeTruthy();

    expect(payloads[4]).toBe("[DONE]");
  });

  it("message 为空返回 400", async () => {
    const env = makeEnv();
    const ctx = makeCtx();
    const req = makeRequest("/chat/stream", {
      method: "POST",
      token: VALID_TOKEN,
      body: { message: "" },
    });
    const resp = await worker.fetch(req, env, ctx);
    expect(resp.status).toBe(400);
    const data = await resp.json();
    expect(data.error).toMatch(/message/);
  });

  it("请求体不是合法 JSON 返回 400", async () => {
    const env = makeEnv();
    const ctx = makeCtx();
    const req = makeRequest("/chat/stream", {
      method: "POST",
      token: VALID_TOKEN,
      body: "{not json",
    });
    const resp = await worker.fetch(req, env, ctx);
    expect(resp.status).toBe(400);
  });

  it("上游 LLM 抛错时通过 SSE error 事件返回（不暴露 5xx）", async () => {
    // 让模拟的 LLM 流式调用抛错
    mocks.llmStream = async function* () {
      throw new Error("upstream 500");
    };
    const env = makeEnv();
    const ctx = makeCtx();
    const req = makeRequest("/chat/stream", {
      method: "POST",
      token: VALID_TOKEN,
      body: { message: "hi" },
    });
    const resp = await worker.fetch(req, env, ctx);
    // 流式响应本身仍是 200（错误通过 SSE 事件传递）
    expect(resp.status).toBe(200);
    const text = await resp.text();
    await Promise.all(ctx._pending);

    const payloads = parseSSEData(text);
    const errPayload = payloads.map((p) => {
      try {
        return JSON.parse(p);
      } catch (_) {
        return null;
      }
    }).find((o) => o && o.type === "error");
    expect(errPayload).toBeTruthy();
    expect(errPayload.message).toBeTruthy();
  });

  it("限流触发返回 429 + Retry-After 头", async () => {
    // 让模拟限流器返回拒绝
    mocks.rateLimit = { allowed: false, retryAfter: 60 };
    const env = makeEnv();
    const ctx = makeCtx();
    const req = makeRequest("/chat/stream", {
      method: "POST",
      token: VALID_TOKEN,
      body: { message: "hi" },
    });
    const resp = await worker.fetch(req, env, ctx);
    expect(resp.status).toBe(429);
    expect(resp.headers.get("Retry-After")).toBe("60");
    const data = await resp.json();
    expect(data.error).toMatch(/rate/i);
  });
});
