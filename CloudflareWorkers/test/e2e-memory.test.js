/**
 * 记忆路由端到端测试（读写/搜索/删除）
 *
 * 通过 worker.fetch 走完整 鉴权 → 路由分发 → memory handler 链路。
 * KV（bff_tokens）与 D1（DB）均用内存 Mock，不依赖真实 Cloudflare。
 * memory 路由不依赖 WASM，故无需 vi.mock。
 */

import { describe, it, expect } from "vitest";
import worker from "../worker.js";

// ============ 测试基础设施 ============

const VALID_TOKEN = "bff-token-mem";
const USER_ID = "user-mem-1";

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

function memRow(overrides = {}) {
  return {
    id: "mem-1",
    user_id: USER_ID,
    content: "用户喜欢咖啡",
    category: "preference",
    importance: 0.8,
    source_conversation_id: null,
    created_at: 1000,
    ...overrides,
  };
}

// ============ 测试用例 ============

describe("E2E /memory", () => {
  it("缺少 X-BFF-Token 返回 401", async () => {
    const env = makeEnv();
    const req = makeRequest("/memory", { method: "GET" });
    const resp = await worker.fetch(req, env, {});
    expect(resp.status).toBe(401);
  });

  it("POST /memory 创建记忆返回 201", async () => {
    const env = makeEnv([
      ["INSERT INTO memories", { run: () => ({ success: true, changes: 1 }) }],
    ]);
    const req = makeRequest("/memory", {
      method: "POST",
      token: VALID_TOKEN,
      body: { content: "用户喜欢咖啡", category: "preference", importance: 0.8 },
    });
    const resp = await worker.fetch(req, env, {});
    expect(resp.status).toBe(201);
    const data = await resp.json();
    expect(data.memory.id).toBeTruthy();
    expect(data.memory.user_id).toBe(USER_ID);
    expect(data.memory.content).toBe("用户喜欢咖啡");
    expect(data.memory.category).toBe("preference");
    expect(data.memory.importance).toBe(0.8);
  });

  it("POST /memory 缺 content 返回 400", async () => {
    const env = makeEnv();
    const req = makeRequest("/memory", {
      method: "POST",
      token: VALID_TOKEN,
      body: { category: "x" },
    });
    const resp = await worker.fetch(req, env, {});
    expect(resp.status).toBe(400);
  });

  it("POST /memory 持久化失败返回 500", async () => {
    // createMemory 通过 try/catch 判断失败：run() 抛错即视为持久化失败
    const env = makeEnv([
      [
        "INSERT INTO memories",
        {
          run: () => {
            throw new Error("D1 write failed");
          },
        },
      ],
    ]);
    const req = makeRequest("/memory", {
      method: "POST",
      token: VALID_TOKEN,
      body: { content: "x" },
    });
    const resp = await worker.fetch(req, env, {});
    expect(resp.status).toBe(500);
  });

  it("GET /memory 列出当前用户记忆", async () => {
    const rows = [memRow({ id: "m1" }), memRow({ id: "m2", content: "用户养猫" })];
    const env = makeEnv([
      ["FROM memories WHERE user_id", { all: () => ({ results: rows }) }],
    ]);
    const req = makeRequest("/memory", { method: "GET", token: VALID_TOKEN });
    const resp = await worker.fetch(req, env, {});
    expect(resp.status).toBe(200);
    const data = await resp.json();
    expect(data.memories).toHaveLength(2);
    expect(data.memories.map((m) => m.id)).toEqual(["m1", "m2"]);
  });

  it("GET /memory?category=xxx 按分类过滤", async () => {
    const rows = [memRow({ id: "m1", category: "preference" })];
    const env = makeEnv([
      ["AND category = ?2", { all: () => ({ results: rows }) }],
    ]);
    const req = makeRequest("/memory?category=preference", {
      method: "GET",
      token: VALID_TOKEN,
    });
    const resp = await worker.fetch(req, env, {});
    expect(resp.status).toBe(200);
    const data = await resp.json();
    expect(data.memories).toHaveLength(1);
  });

  it("POST /memory/search 返回匹配记忆", async () => {
    const rows = [memRow({ id: "m1", content: "用户喜欢咖啡" })];
    const env = makeEnv([
      ["content LIKE", { all: () => ({ results: rows }) }],
    ]);
    const req = makeRequest("/memory/search", {
      method: "POST",
      token: VALID_TOKEN,
      body: { query: "咖啡", limit: 5 },
    });
    const resp = await worker.fetch(req, env, {});
    expect(resp.status).toBe(200);
    const data = await resp.json();
    expect(data.query).toBe("咖啡");
    expect(data.memories).toHaveLength(1);
    expect(data.memories[0].content).toContain("咖啡");
  });

  it("POST /memory/search 缺 query 返回 400", async () => {
    const env = makeEnv();
    const req = makeRequest("/memory/search", {
      method: "POST",
      token: VALID_TOKEN,
      body: { limit: 5 },
    });
    const resp = await worker.fetch(req, env, {});
    expect(resp.status).toBe(400);
  });

  it("POST /memory/search 无 DB 时降级返回空数组（200）", async () => {
    // 不配置 DB → fetchRelevantMemories 返回 []
    const env = { bff_tokens: makeKV() };
    const req = makeRequest("/memory/search", {
      method: "POST",
      token: VALID_TOKEN,
      body: { query: "anything" },
    });
    const resp = await worker.fetch(req, env, {});
    expect(resp.status).toBe(200);
    const data = await resp.json();
    expect(data.memories).toEqual([]);
  });

  it("DELETE /memory/:id 成功返回 deleted:true", async () => {
    const env = makeEnv([
      ["DELETE FROM memories WHERE id = ?1 AND user_id", { run: () => ({ success: true, changes: 1 }) }],
    ]);
    const req = makeRequest("/memory/mem-1", {
      method: "DELETE",
      token: VALID_TOKEN,
    });
    const resp = await worker.fetch(req, env, {});
    expect(resp.status).toBe(200);
    const data = await resp.json();
    expect(data.deleted).toBe(true);
    expect(data.id).toBe("mem-1");
  });

  it("DELETE /memory/:id 不存在返回 404", async () => {
    const env = makeEnv([
      ["DELETE FROM memories WHERE id = ?1 AND user_id", { run: () => ({ success: true, changes: 0 }) }],
    ]);
    const req = makeRequest("/memory/nope", {
      method: "DELETE",
      token: VALID_TOKEN,
    });
    const resp = await worker.fetch(req, env, {});
    expect(resp.status).toBe(404);
  });
});
