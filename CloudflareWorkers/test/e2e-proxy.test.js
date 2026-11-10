/**
 * LLM 兜底透传代理端到端测试（P1-5）
 *
 * 覆盖：TTL 鉴权、路径白名单、模型白名单、请求体大小上限、
 * Header 白名单与上游注入、限流与未知 provider。
 * KV 与上游 fetch 均用 Mock；WASM 限流器用纯 JS 替身。
 */

import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";

const mocks = vi.hoisted(() => ({
  rateLimit: { allowed: true, remaining: 59 },
}));

vi.mock("../src/lib/ratelimit.js", async (importActual) => {
  const actual = await importActual();
  return {
    ...actual,
    checkRateLimit: async () => mocks.rateLimit,
  };
});

import worker from "../worker.js";

const VALID_TOKEN = "bff-token-valid";
const EXPIRED_TOKEN = "bff-token-expired";
const USER_ID = "user-proxy-1";

function makeEnv() {
  const store = new Map();
  store.set(
    VALID_TOKEN,
    JSON.stringify({
      userId: USER_ID,
      expiresAt: new Date(Date.now() + 3600_000).toISOString(),
    })
  );
  store.set(
    EXPIRED_TOKEN,
    JSON.stringify({
      userId: "user-expired",
      expiresAt: "2000-01-01T00:00:00.000Z",
    })
  );
  return {
    bff_tokens: {
      get: async (key) => (store.has(key) ? store.get(key) : null),
    },
    DEEPSEEK_API_KEY: "deepseek-key",
    DEEPSEEK_BASE_URL: "https://deepseek.test",
    QWEN_API_KEY: "qwen-key",
    QWEN_BASE_URL: "https://qwen.test",
  };
}

function makeCtx() {
  const pending = [];
  return {
    waitUntil: (p) => {
      pending.push(Promise.resolve(p).catch(() => {}));
    },
    _pending: pending,
  };
}

function makeRequest(path, { token = VALID_TOKEN, provider, body, headers = {} } = {}) {
  const h = new Headers(headers);
  if (token) h.set("X-BFF-Token", token);
  if (provider) h.set("X-Provider", provider);
  if (!h.has("Content-Type")) h.set("Content-Type", "application/json");
  return new Request("https://bff.test" + path, {
    method: "POST",
    headers: h,
    body: typeof body === "string" ? body : JSON.stringify(body),
  });
}

let fetchMock;

beforeEach(() => {
  mocks.rateLimit = { allowed: true, remaining: 59 };
  fetchMock = vi.fn(async () =>
    new Response('data: {"ok":true}\n\n', {
      status: 200,
      headers: { "Content-Type": "text/event-stream" },
    })
  );
  vi.stubGlobal("fetch", fetchMock);
});

afterEach(() => {
  vi.unstubAllGlobals();
});

const chatBody = { model: "deepseek-chat", messages: [{ role: "user", content: "hi" }] };

describe("E2E / POST 兜底代理", () => {
  it("缺少 token 返回 401 且不调用上游", async () => {
    const resp = await worker.fetch(
      makeRequest("/v1/chat/completions", { token: null, body: chatBody }),
      makeEnv(),
      makeCtx()
    );
    expect(resp.status).toBe(401);
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("过期 token 返回 401（复用 authenticate 的 TTL 校验）", async () => {
    const resp = await worker.fetch(
      makeRequest("/v1/chat/completions", { token: EXPIRED_TOKEN, body: chatBody }),
      makeEnv(),
      makeCtx()
    );
    expect(resp.status).toBe(401);
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("非白名单路径返回 404 且不调用上游", async () => {
    const resp = await worker.fetch(
      makeRequest("/v1/models", { body: chatBody }),
      makeEnv(),
      makeCtx()
    );
    expect(resp.status).toBe(404);
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("路径穿越/额外层级返回 404", async () => {
    const resp = await worker.fetch(
      makeRequest("/v1/chat/completions/../../admin", { body: chatBody }),
      makeEnv(),
      makeCtx()
    );
    // URL 解析会归一化 ..，最终不匹配白名单
    expect(resp.status).toBe(404);
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("不允许的 model 返回 400 且不调用上游", async () => {
    const resp = await worker.fetch(
      makeRequest("/v1/chat/completions", {
        body: { model: "gpt-4o", messages: [] },
      }),
      makeEnv(),
      makeCtx()
    );
    expect(resp.status).toBe(400);
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("provider 与 model 不匹配返回 400", async () => {
    const resp = await worker.fetch(
      makeRequest("/v1/chat/completions", {
        provider: "qwen",
        body: { model: "deepseek-chat", messages: [] },
      }),
      makeEnv(),
      makeCtx()
    );
    expect(resp.status).toBe(400);
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("embedding 路径使用 chat 模型返回 400", async () => {
    const resp = await worker.fetch(
      makeRequest("/v1/embeddings", {
        body: { model: "deepseek-chat", input: ["x"] },
      }),
      makeEnv(),
      makeCtx()
    );
    expect(resp.status).toBe(400);
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("请求体超过 1 MiB 返回 413", async () => {
    const big = "a".repeat(1024 * 1024);
    const resp = await worker.fetch(
      makeRequest("/v1/chat/completions", {
        body: { model: "deepseek-chat", messages: [{ role: "user", content: big }] },
      }),
      makeEnv(),
      makeCtx()
    );
    expect(resp.status).toBe(413);
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("未知 provider 返回 400", async () => {
    const resp = await worker.fetch(
      makeRequest("/v1/chat/completions", {
        provider: "unknown",
        body: chatBody,
      }),
      makeEnv(),
      makeCtx()
    );
    expect(resp.status).toBe(400);
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("限流触发返回 429 + Retry-After", async () => {
    mocks.rateLimit = { allowed: false, retryAfter: 30 };
    const resp = await worker.fetch(
      makeRequest("/v1/chat/completions", { body: chatBody }),
      makeEnv(),
      makeCtx()
    );
    expect(resp.status).toBe(429);
    expect(resp.headers.get("Retry-After")).toBe("30");
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("合法请求转发到上游：路径归一化、注入 Authorization、剥离客户端头", async () => {
    const ctx = makeCtx();
    const req = makeRequest("/v1/chat/completions/", {
      body: chatBody,
      headers: { "X-Custom": "should-not-forward" },
    });
    const resp = await worker.fetch(req, makeEnv(), ctx);
    expect(resp.status).toBe(200);
    expect(await resp.text()).toContain('"ok":true');
    await Promise.all(ctx._pending);

    expect(fetchMock).toHaveBeenCalledTimes(1);
    const upstreamReq = fetchMock.mock.calls[0][0];
    expect(upstreamReq.url).toBe("https://deepseek.test/v1/chat/completions");

    const headers = upstreamReq.headers;
    expect(headers.get("Authorization")).toBe("Bearer deepseek-key");
    expect(headers.get("Content-Type")).toBe("application/json");
    expect(headers.get("X-BFF-Token")).toBeNull();
    expect(headers.get("X-Provider")).toBeNull();
    expect(headers.get("X-Custom")).toBeNull();

    expect(JSON.parse(await upstreamReq.text())).toEqual(chatBody);
  });

  it("客户端断开时上游请求 signal 随之 abort", async () => {
    const controller = new AbortController();
    const h = new Headers({ "Content-Type": "application/json" });
    h.set("X-BFF-Token", VALID_TOKEN);
    const req = new Request("https://bff.test/v1/chat/completions", {
      method: "POST",
      headers: h,
      body: JSON.stringify(chatBody),
      signal: controller.signal,
    });
    const ctx = makeCtx();
    const resp = await worker.fetch(req, makeEnv(), ctx);
    expect(resp.status).toBe(200);
    expect(await resp.text()).toContain('"ok":true');
    await Promise.all(ctx._pending);

    // Request 构造会派生跟随信号（非同引用），验证 abort 行为传播
    const upstreamReq = fetchMock.mock.calls[0][0];
    expect(upstreamReq.signal.aborted).toBe(false);
    controller.abort();
    expect(upstreamReq.signal.aborted).toBe(true);
  });

  it("embedding 请求按 provider 路由到对应上游", async () => {
    const ctx = makeCtx();
    const resp = await worker.fetch(
      makeRequest("/v1/embeddings", {
        provider: "qwen",
        body: { model: "text-embedding-v3", input: ["hello"] },
      }),
      makeEnv(),
      ctx
    );
    expect(resp.status).toBe(200);
    // 先消费响应体，避免上游流因背压无法完成
    expect(await resp.text()).toContain('"ok":true');
    await Promise.all(ctx._pending);

    const upstreamReq = fetchMock.mock.calls[0][0];
    expect(upstreamReq.url).toBe("https://qwen.test/v1/embeddings");
    expect(upstreamReq.headers.get("Authorization")).toBe("Bearer qwen-key");
  });
});
