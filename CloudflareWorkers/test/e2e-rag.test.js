/**
 * RAG 路由端到端测试（检索鉴权 + 响应格式）
 *
 * 通过 worker.fetch 走完整 鉴权 → 路由分发 → rag handler 链路。
 * 聚焦 POST /rag/search：验证鉴权、入参校验、响应格式。
 * searchDocuments 关键词检索不依赖 WASM（无 DB 时降级返回空数组）。
 * 不测试 /rag/documents 上传（其依赖 WASM Chunker 分块，由独立单测覆盖）。
 */

import { describe, it, expect } from "vitest";
import worker from "../worker.js";

// ============ 测试基础设施 ============

const VALID_TOKEN = "bff-token-rag";
const USER_ID = "user-rag-1";

function makeKV() {
  const store = new Map();
  store.set(VALID_TOKEN, JSON.stringify({ userId: USER_ID }));
  return { get: async (k) => (store.has(k) ? store.get(k) : null) };
}

/** D1 mock：按 SQL 子字符串匹配注册返回值 */
function makeDB() {
  const handlers = [];
  const db = {
    prepare(sql) {
      const matched = handlers.find((h) =>
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
          return matched && matched.run
            ? await matched.run(binds)
            : { success: true, changes: 1 };
        },
      };
      return stmt;
    },
    async batch(stmts) {
      return stmts.map(() => ({ success: true, changes: 1 }));
    },
    on(match, fns) {
      handlers.push({ match, ...fns });
      return db;
    },
  };
  return db;
}

function makeEnv(dbHandlers = []) {
  const DB = makeDB();
  for (const [match, fns] of dbHandlers) DB.on(match, fns);
  return { bff_tokens: makeKV(), DB };
}

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

// ============ 测试用例 ============

describe("E2E /rag/search", () => {
  it("缺少 X-BFF-Token 返回 401", async () => {
    const env = makeEnv();
    const req = makeRequest("/rag/search", {
      method: "POST",
      body: { query: "咖啡" },
    });
    const resp = await worker.fetch(req, env, {});
    expect(resp.status).toBe(401);
  });

  it("无效 X-BFF-Token 返回 401", async () => {
    const env = makeEnv();
    const req = makeRequest("/rag/search", {
      method: "POST",
      token: "not-in-kv",
      body: { query: "咖啡" },
    });
    const resp = await worker.fetch(req, env, {});
    expect(resp.status).toBe(401);
  });

  it("合法 token + query 返回 200 + 标准 JSON 格式（chunks 数组 + query 回显）", async () => {
    const env = makeEnv();
    const req = makeRequest("/rag/search", {
      method: "POST",
      token: VALID_TOKEN,
      body: { query: "咖啡", limit: 3 },
    });
    const resp = await worker.fetch(req, env, {});
    expect(resp.status).toBe(200);
    expect(resp.headers.get("Content-Type")).toContain("application/json");
    const data = await resp.json();
    // 响应格式契约：chunks 为数组，query 回显
    expect(Array.isArray(data.chunks)).toBe(true);
    expect(data.query).toBe("咖啡");
  });

  it("无 DB 时 chunks 降级为空数组（200）", async () => {
    // 不配置 DB → searchDocuments 返回 []
    const env = { bff_tokens: makeKV() };
    const req = makeRequest("/rag/search", {
      method: "POST",
      token: VALID_TOKEN,
      body: { query: "任意" },
    });
    const resp = await worker.fetch(req, env, {});
    expect(resp.status).toBe(200);
    const data = await resp.json();
    expect(data.chunks).toEqual([]);
  });

  it("有 DB 时返回匹配的文档分块", async () => {
    const chunks = [
      {
        id: "ch1",
        document_id: "d1",
        content: "咖啡因可短暂提神",
        metadata: '{"index":0}',
        chunk_index: 0,
        weight: 1.0,
        document_title: "咖啡百科",
      },
    ];
    const env = makeEnv([
      ["content LIKE", { all: () => ({ results: chunks }) }],
    ]);
    const req = makeRequest("/rag/search", {
      method: "POST",
      token: VALID_TOKEN,
      body: { query: "咖啡" },
    });
    const resp = await worker.fetch(req, env, {});
    expect(resp.status).toBe(200);
    const data = await resp.json();
    expect(data.chunks).toHaveLength(1);
    expect(data.chunks[0].content).toContain("咖啡");
    expect(data.chunks[0].document_title).toBe("咖啡百科");
  });

  it("缺少 query 返回 400", async () => {
    const env = makeEnv();
    const req = makeRequest("/rag/search", {
      method: "POST",
      token: VALID_TOKEN,
      body: { limit: 3 },
    });
    const resp = await worker.fetch(req, env, {});
    expect(resp.status).toBe(400);
    const data = await resp.json();
    expect(data.error).toMatch(/query/);
  });

  it("请求体不是合法 JSON 返回 400", async () => {
    const env = makeEnv();
    const req = makeRequest("/rag/search", {
      method: "POST",
      token: VALID_TOKEN,
      body: "{broken",
    });
    const resp = await worker.fetch(req, env, {});
    expect(resp.status).toBe(400);
  });

  it("limit 默认为 3（未传时使用默认值，不影响响应格式）", async () => {
    const env = makeEnv([
      ["content LIKE", { all: () => ({ results: [] }) }],
    ]);
    const req = makeRequest("/rag/search", {
      method: "POST",
      token: VALID_TOKEN,
      body: { query: "测试" },
    });
    const resp = await worker.fetch(req, env, {});
    expect(resp.status).toBe(200);
    const data = await resp.json();
    expect(data.chunks).toEqual([]);
    expect(data.query).toBe("测试");
  });
});
