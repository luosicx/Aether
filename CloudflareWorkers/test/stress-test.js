/**
 * 限流压力测试（纯 Node.js，不依赖 k6）
 *
 * 用 Promise.all 并发触发 /chat/stream 请求，验证 worker 的限流集成：
 *   - 容量耗尽后返回 429 + Retry-After
 *   - 并发下恰好放行 capacity 个、拒绝其余（无误杀、无超放）
 *
 * checkRateLimit（WASM 令牌桶）用 vi.mock 替换为等价的 JS 令牌桶：
 * acquire 为同步减量，保证并发下计数精确。WASM 令牌桶的算法正确性由
 * ratelimit.wasm.test.js 单测覆盖，此处聚焦 worker 限流集成与并发行为。
 * callLLMStream / redact 同样 mock，避免依赖 WASM 与上游 API。
 */

import { describe, it, expect, vi } from "vitest";

const mocks = vi.hoisted(() => ({
  // 令牌桶容量（每个用例可调整）
  capacity: 5,
  // 当前剩余令牌（每个用例前重置）
  bucket: { tokens: 5 },
}));

// 模拟限流器：JS 令牌桶，acquire 同步减量
vi.mock("../src/lib/ratelimit.js", async (importActual) => {
  const actual = await importActual();
  return {
    ...actual,
    checkRateLimit: async () => {
      if (mocks.bucket.tokens >= 1) {
        mocks.bucket.tokens -= 1;
        return { allowed: true, remaining: mocks.bucket.tokens };
      }
      return { allowed: false, retryAfter: 1 };
    },
  };
});

// 模拟 LLM 流式调用：产出单个增量即结束（仅为了让放行请求返回 200 SSE）
vi.mock("../src/lib/llm.js", async (importActual) => {
  const actual = await importActual();
  return {
    ...actual,
    callLLMStream: async function* () {
      yield "ok";
    },
  };
});

vi.mock("../src/lib/redact.js", () => ({
  redact: async (s) => (s == null ? "" : String(s)),
}));

import worker from "../worker.js";

// ============ 测试基础设施 ============

const VALID_TOKEN = "bff-token-stress";
const USER_ID = "user-stress-1";

function makeKV() {
  const store = new Map();
  store.set(VALID_TOKEN, JSON.stringify({ userId: USER_ID }));
  return { get: async (k) => (store.has(k) ? store.get(k) : null) };
}

function makeEnv() {
  return {
    bff_tokens: makeKV(),
    DEEPSEEK_API_KEY: "mock",
    DEEPSEEK_BASE_URL: "https://deepseek.test",
    QWEN_API_KEY: "mock",
    QWEN_BASE_URL: "https://qwen.test",
  };
}

/** 共享 ctx：收集所有 waitUntil 后台任务 */
function makeCtx() {
  const pending = [];
  return {
    waitUntil: (p) => {
      pending.push(Promise.resolve(p).catch(() => {}));
    },
    _pending: pending,
  };
}

function makeChatRequest() {
  return new Request("https://bff.test/chat/stream", {
    method: "POST",
    headers: {
      "X-BFF-Token": VALID_TOKEN,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ message: "hi" }),
  });
}

/**
 * 并发发起 n 个 /chat/stream 请求，返回所有响应（已读取 body 以排空流）。
 * @param {number} n
 * @returns {Promise<Array<{status:number, retryAfter:string|null}>>}
 */
async function fireConcurrent(n) {
  const env = makeEnv();
  const ctx = makeCtx();
  const requests = Array.from({ length: n }, () => makeChatRequest());
  const responses = await Promise.all(
    requests.map((req) => worker.fetch(req, env, ctx))
  );
  // 读取所有 body：200 响应的 SSE 流需排空才能让后台 streamTask 完成
  await Promise.all(
    responses.map((r) => r.text().catch(() => ""))
  );
  // 等待所有后台任务完成，避免悬挂
  await Promise.all(ctx._pending);

  return responses.map((r) => ({
    status: r.status,
    retryAfter: r.headers.get("Retry-After"),
  }));
}

/** 重置令牌桶 */
function resetBucket(capacity) {
  mocks.capacity = capacity;
  mocks.bucket.tokens = capacity;
}

// ============ 测试用例 ============

describe("限流压力测试 /chat/stream", () => {
  it("容量 5、并发 20：恰好放行 5、拒绝 15，拒绝均返回 429 + Retry-After", async () => {
    resetBucket(5);
    const results = await fireConcurrent(20);

    const ok = results.filter((r) => r.status === 200);
    const limited = results.filter((r) => r.status === 429);

    expect(ok).toHaveLength(5);
    expect(limited).toHaveLength(15);
    // 所有 429 必须携带 Retry-After 头
    for (const r of limited) {
      expect(r.retryAfter).not.toBeNull();
      expect(Number(r.retryAfter)).toBeGreaterThan(0);
    }
    // 总数对齐
    expect(ok.length + limited.length).toBe(20);
  });

  it("容量 ≥ 并发数时全部放行（无误杀）", async () => {
    resetBucket(30);
    const results = await fireConcurrent(20);
    const ok = results.filter((r) => r.status === 200);
    const limited = results.filter((r) => r.status === 429);
    expect(ok).toHaveLength(20);
    expect(limited).toHaveLength(0);
  });

  it("容量 1、并发 10：仅放行 1 个", async () => {
    resetBucket(1);
    const results = await fireConcurrent(10);
    const ok = results.filter((r) => r.status === 200);
    const limited = results.filter((r) => r.status === 429);
    expect(ok).toHaveLength(1);
    expect(limited).toHaveLength(9);
  });

  it("容量 0：全部被限流（429）", async () => {
    resetBucket(0);
    const results = await fireConcurrent(5);
    const ok = results.filter((r) => r.status === 200);
    const limited = results.filter((r) => r.status === 429);
    expect(ok).toHaveLength(0);
    expect(limited).toHaveLength(5);
    for (const r of limited) {
      expect(r.status).toBe(429);
      expect(r.retryAfter).not.toBeNull();
    }
  });

  it("高并发 100 请求容量 10：放行数严格等于容量（无超放）", async () => {
    resetBucket(10);
    const results = await fireConcurrent(100);
    const ok = results.filter((r) => r.status === 200);
    const limited = results.filter((r) => r.status === 429);
    expect(ok).toHaveLength(10);
    expect(limited).toHaveLength(90);
  });
});
