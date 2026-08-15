/**
 * 安全整改回归测试（第一批 hotfix + 第二批扩展）
 *
 * 覆盖：
 * 1. Token SHA-256 哈希 KV 键（新格式生效 + 旧明文键自动迁移）
 * 2. CORS（Origin 白名单：预检 204 / 放行回显 / 非白名单不下发头）
 * 3. LLM 透传代理路径白名单（非白名单路径 404，不再任意透传 + 借用上游 API Key）
 * 4. joinUpstreamUrl（Qwen baseUrl 含 /v1 不再双拼）
 * 5. 上游 Header 白名单（X-BFF-Token / Cookie 不透传，Authorization 注入）
 * 6. 【第二批】上游 Header 附加白名单（env.UPSTREAM_EXTRA_HEADERS 可配置扩展，
 *    凭证/代理类敏感头永久拒绝，误配置也不透传）
 *
 * 说明：本文件不 mock ratelimit.js，顺带覆盖 WASM 不可用时的纯 JS 令牌桶降级路径。
 * Durable Object 全局限流见 test/ratelimit-do.test.js。
 */

import { describe, it, expect, vi } from "vitest";
import { createHash } from "node:crypto";
import { joinUpstreamUrl, buildUpstreamHeaders } from "../src/lib/llm.js";
import worker from "../worker.js";

// ============ 测试基础设施 ============

const TOKEN = "bff-token-sec";
const USER_ID = "user-sec-1";
const ALLOWED_ORIGIN = "https://app.aether.example.com";

/** 与 src/lib/auth.js 的 tokenKey 保持一致的哈希键算法 */
function sha256Key(token) {
  return "sha256:" + createHash("sha256").update(token, "utf8").digest("hex");
}

/** KV mock（含 put/delete，支持迁移断言） */
function makeKV(seed = new Map()) {
  const store = seed;
  return {
    get: async (k) => (store.has(k) ? store.get(k) : null),
    put: async (k, v) => {
      store.set(k, v);
    },
    delete: async (k) => {
      store.delete(k);
    },
  };
}

/** D1 mock（与 e2e-conversations 同款：按 SQL 子串匹配注册返回值）
 *  handlers 支持元组格式 [match, fns]（与 e2e-conversations 的 makeEnv 对齐） */
function makeDB(handlers = []) {
  const list = handlers.map((h) => (Array.isArray(h) ? { match: h[0], ...h[1] } : h));
  return {
    prepare(sql) {
      const matched = list.find((h) =>
        h.match instanceof RegExp ? h.match.test(sql) : sql.includes(h.match)
      );
      let binds = [];
      const stmt = {
        bind(...args) {
          binds = args;
          return stmt;
        },
        async first() {
          return matched && matched.first ? await matched.first(binds) : null;
        },
        async all() {
          return matched && matched.all ? await matched.all(binds) : { results: [] };
        },
        async run() {
          return matched && matched.run ? await matched.run(binds) : { success: true, changes: 1 };
        },
      };
      return stmt;
    },
  };
}

/** 构造 env */
function makeEnv({ kvSeed = new Map(), dbHandlers = [], extra = {} } = {}) {
  return {
    bff_tokens: makeKV(kvSeed),
    DB: makeDB(dbHandlers),
    ALLOWED_ORIGINS: ALLOWED_ORIGIN,
    DEEPSEEK_BASE_URL: "https://api.deepseek.com",
    DEEPSEEK_API_KEY: "sk-test",
    ...extra,
  };
}

/** 构造 Request */
function makeRequest(path, { method = "GET", token, body, headers = {} } = {}) {
  const h = new Headers(headers);
  if (token) h.set("X-BFF-Token", TOKEN);
  const init = { method, headers: h };
  if (body !== undefined) {
    init.body = typeof body === "string" ? body : JSON.stringify(body);
    if (!h.has("Content-Type")) h.set("Content-Type", "application/json");
  }
  return new Request("https://bff.test" + path, init);
}

/** 仅含哈希键的 KV 种子（新格式 token） */
function hashedSeed() {
  return new Map([[sha256Key(TOKEN), JSON.stringify({ userId: USER_ID })]]);
}

// ============ 测试用例 ============

describe("auth: Token SHA-256 哈希 KV 键", () => {
  it("KV 仅存哈希键时鉴权通过（新格式生效，明文 token 不落 KV）", async () => {
    const env = makeEnv({
      kvSeed: hashedSeed(),
      dbHandlers: [["WHERE user_id = ?1 ORDER BY", { all: () => ({ results: [] }) }]],
    });
    const resp = await worker.fetch(makeRequest("/conversations", { token: true }), env, {});
    expect(resp.status).toBe(200);
  });

  it("旧明文键首次命中后自动迁移为哈希键并删除明文键", async () => {
    const seed = new Map([[TOKEN, JSON.stringify({ userId: USER_ID })]]);
    const env = makeEnv({
      kvSeed: seed,
      dbHandlers: [["WHERE user_id = ?1 ORDER BY", { all: () => ({ results: [] }) }]],
    });
    const resp = await worker.fetch(makeRequest("/conversations", { token: true }), env, {});
    expect(resp.status).toBe(200);
    expect(seed.has(sha256Key(TOKEN))).toBe(true);
    expect(seed.has(TOKEN)).toBe(false);
  });
});

describe("CORS: Origin 白名单", () => {
  it("OPTIONS 预检：白名单 Origin 返回 204 + CORS 头", async () => {
    const env = makeEnv({ kvSeed: new Map() });
    const req = makeRequest("/conversations", {
      method: "OPTIONS",
      headers: {
        Origin: ALLOWED_ORIGIN,
        "Access-Control-Request-Method": "GET",
        "Access-Control-Request-Headers": "X-BFF-Token",
      },
    });
    const resp = await worker.fetch(req, env, {});
    expect(resp.status).toBe(204);
    expect(resp.headers.get("Access-Control-Allow-Origin")).toBe(ALLOWED_ORIGIN);
    expect(resp.headers.get("Access-Control-Allow-Headers")).toContain("X-BFF-Token");
  });

  it("OPTIONS 预检：非白名单 Origin 不下发任何 CORS 头", async () => {
    const env = makeEnv({ kvSeed: new Map() });
    const req = makeRequest("/conversations", {
      method: "OPTIONS",
      headers: { Origin: "https://evil.example.com", "Access-Control-Request-Method": "GET" },
    });
    const resp = await worker.fetch(req, env, {});
    expect(resp.status).toBe(204);
    expect(resp.headers.get("Access-Control-Allow-Origin")).toBeNull();
  });

  it("未配置 ALLOWED_ORIGINS 时不放开跨域（默认拒绝）", async () => {
    const env = makeEnv({ kvSeed: new Map(), extra: { ALLOWED_ORIGINS: "" } });
    const req = makeRequest("/conversations", {
      method: "OPTIONS",
      headers: { Origin: ALLOWED_ORIGIN, "Access-Control-Request-Method": "GET" },
    });
    const resp = await worker.fetch(req, env, {});
    expect(resp.headers.get("Access-Control-Allow-Origin")).toBeNull();
  });

  it("普通请求：白名单 Origin 的响应带 ACAO + Vary", async () => {
    const env = makeEnv({
      kvSeed: hashedSeed(),
      dbHandlers: [["WHERE user_id = ?1 ORDER BY", { all: () => ({ results: [] }) }]],
    });
    const req = makeRequest("/conversations", {
      method: "GET",
      token: true,
      headers: { Origin: ALLOWED_ORIGIN },
    });
    const resp = await worker.fetch(req, env, {});
    expect(resp.status).toBe(200);
    expect(resp.headers.get("Access-Control-Allow-Origin")).toBe(ALLOWED_ORIGIN);
    expect(resp.headers.get("Vary")).toContain("Origin");
  });
});

describe("proxyLLM: 路径白名单", () => {
  it("非白名单路径 POST 返回 404（不再任意路径透传 + 借用上游 API Key）", async () => {
    const env = makeEnv({ kvSeed: hashedSeed() });
    const req = makeRequest("/v1/anything/else", { method: "POST", token: true, body: {} });
    const resp = await worker.fetch(req, env, {});
    expect(resp.status).toBe(404);
  });

  it("账户/计费类上游路径被拒绝", async () => {
    const env = makeEnv({ kvSeed: hashedSeed() });
    const req = makeRequest("/v1/billing/usage", { method: "POST", token: true, body: {} });
    const resp = await worker.fetch(req, env, {});
    expect(resp.status).toBe(404);
  });
});

describe("proxyLLM: 上游转发（白名单路径）", () => {
  it("URL 归一化（无 /v1/v1 双拼）+ Header 白名单 + Authorization 注入", async () => {
    const fetchSpy = vi.spyOn(globalThis, "fetch").mockResolvedValue(
      new Response(JSON.stringify({ ok: true }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      })
    );
    try {
      const env = makeEnv({
        kvSeed: hashedSeed(),
        extra: {
          // 故意配置已含 /v1 的 baseUrl（旧 wrangler.toml 形态），验证归一化兜底
          QWEN_BASE_URL: "https://dashscope.aliyuncs.com/compatible-mode/v1",
          QWEN_API_KEY: "sk-qwen",
        },
      });
      const req = makeRequest("/v1/chat/completions", {
        method: "POST",
        token: true,
        body: { model: "qwen-plus" },
        headers: { "X-Provider": "qwen", Cookie: "session=leak-me" },
      });
      const resp = await worker.fetch(req, env, { waitUntil: () => {} });
      expect(resp.status).toBe(200);

      expect(fetchSpy).toHaveBeenCalledTimes(1);
      const calledReq = fetchSpy.mock.calls[0][0];
      // /v1/v1 双拼修复：baseUrl 已含 /v1 时不重复拼接
      expect(calledReq.url).toBe(
        "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
      );
      // Header 白名单：注入 Authorization，剥离 X-BFF-Token 与 Cookie
      expect(calledReq.headers.get("Authorization")).toBe("Bearer sk-qwen");
      expect(calledReq.headers.get("X-BFF-Token")).toBeNull();
      expect(calledReq.headers.get("Cookie")).toBeNull();
    } finally {
      fetchSpy.mockRestore();
    }
  });
});

describe("buildUpstreamHeaders: 附加白名单（第二批整改）", () => {
  it("extraAllowed 中的 header 透传（如 x-request-id）", () => {
    const h = new Headers({
      "Content-Type": "application/json",
      "X-Request-Id": "req-123",
      "X-App-Version": "3.0.0",
      "X-Custom-Trace": "trace-abc",
    });
    const out = buildUpstreamHeaders(h, "sk-test", "x-request-id,x-custom-trace");
    expect(out.get("X-Request-Id")).toBe("req-123");
    expect(out.get("X-Custom-Trace")).toBe("trace-abc");
    // 未配置的附加头仍被剥离
    expect(out.get("X-App-Version")).toBeNull();
    expect(out.get("Authorization")).toBe("Bearer sk-test");
  });

  it("永久拒绝清单：extra 配置敏感头也不透传", () => {
    const h = new Headers({
      "Content-Type": "application/json",
      Cookie: "session=leak",
      "X-BFF-Token": "bff-secret",
      "X-Forwarded-For": "1.2.3.4",
      "Proxy-Authorization": "Basic xxx",
      "X-Request-Id": "req-1",
    });
    // 恶意/误配置：把敏感头加进 extra
    const out = buildUpstreamHeaders(
      h,
      "sk-test",
      "cookie,x-bff-token,x-forwarded-for,proxy-authorization,x-request-id"
    );
    expect(out.get("Cookie")).toBeNull();
    expect(out.get("X-BFF-Token")).toBeNull();
    expect(out.get("X-Forwarded-For")).toBeNull();
    expect(out.get("Proxy-Authorization")).toBeNull();
    // 非敏感附加头正常透传
    expect(out.get("X-Request-Id")).toBe("req-1");
    expect(out.get("Authorization")).toBe("Bearer sk-test");
  });

  it("extraAllowed 大小写与空白容忍", () => {
    const h = new Headers({ "X-App-Version": "3.0" });
    const out = buildUpstreamHeaders(h, "sk", " X-App-Version , x-app-version ");
    expect(out.get("X-App-Version")).toBe("3.0");
  });

  it("全链路：env.UPSTREAM_EXTRA_HEADERS 经 proxyLLM 生效（含敏感头拦截）", async () => {
    const fetchSpy = vi.spyOn(globalThis, "fetch").mockResolvedValue(
      new Response(JSON.stringify({ ok: true }), { status: 200 })
    );
    try {
      const env = makeEnv({
        kvSeed: hashedSeed(),
        extra: {
          UPSTREAM_EXTRA_HEADERS: "x-request-id,cookie,x-bff-token",
        },
      });
      const req = makeRequest("/v1/chat/completions", {
        method: "POST",
        token: true,
        body: { model: "deepseek-chat" },
        headers: {
          "X-Request-Id": "req-42",
          Cookie: "session=leak",
          "X-BFF-Token": TOKEN,
        },
      });
      const resp = await worker.fetch(req, env, { waitUntil: () => {} });
      expect(resp.status).toBe(200);

      const calledReq = fetchSpy.mock.calls[0][0];
      // 配置的附加白名单头透传
      expect(calledReq.headers.get("X-Request-Id")).toBe("req-42");
      // 永久拒绝清单优先于 extra 配置
      expect(calledReq.headers.get("Cookie")).toBeNull();
      expect(calledReq.headers.get("X-BFF-Token")).toBeNull();
      expect(calledReq.headers.get("Authorization")).toBe("Bearer sk-test");
    } finally {
      fetchSpy.mockRestore();
    }
  });
});

describe("joinUpstreamUrl: URL 归一化", () => {
  it("baseUrl 无 /v1 时正常拼接", () => {
    expect(joinUpstreamUrl("https://api.deepseek.com", "/v1/chat/completions")).toBe(
      "https://api.deepseek.com/v1/chat/completions"
    );
  });

  it("baseUrl 已含 /v1 时不双拼（Qwen compatible-mode 兼容）", () => {
    expect(joinUpstreamUrl("https://x.com/compatible-mode/v1", "/v1/chat/completions")).toBe(
      "https://x.com/compatible-mode/v1/chat/completions"
    );
  });

  it("容忍 baseUrl 末尾斜杠", () => {
    expect(joinUpstreamUrl("https://api.deepseek.com/", "/v1/models")).toBe(
      "https://api.deepseek.com/v1/models"
    );
  });
});
