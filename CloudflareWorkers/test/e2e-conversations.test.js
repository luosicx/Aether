/**
 * 会话路由端到端测试（CRUD）
 *
 * 通过 worker.fetch 走完整 鉴权 → 路由分发 → conversations handler 链路。
 * KV（bff_tokens）与 D1（DB）均用内存 Mock，不依赖真实 Cloudflare。
 * conversations 路由不依赖 WASM，故无需 vi.mock。
 */

import { describe, it, expect } from "vitest";
import worker from "../worker.js";

// ============ 测试基础设施 ============

const VALID_TOKEN = "bff-token-conv";
const USER_ID = "user-conv-1";
const OTHER_USER_ID = "user-other";

/** KV mock */
function makeKV() {
  const store = new Map();
  store.set(VALID_TOKEN, JSON.stringify({ userId: USER_ID }));
  return { get: async (k) => (store.has(k) ? store.get(k) : null) };
}

/**
 * D1 mock：按 SQL 子字符串匹配注册返回值。
 * - prepare(sql).bind(...).first() / .all() / .run()
 * - batch(stmts)
 */
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

/** 构造 env */
function makeEnv(dbHandlers = []) {
  const DB = makeDB();
  for (const [match, fns] of dbHandlers) DB.on(match, fns);
  return {
    bff_tokens: makeKV(),
    DB,
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

/** 会话行 fixture */
function convRow(overrides = {}) {
  return {
    id: "conv-1",
    user_id: USER_ID,
    title: "测试会话",
    parent_id: null,
    created_at: 1000,
    updated_at: 1000,
    last_message_preview: null,
    is_pinned: 0,
    system_prompt: "你是一个有帮助的AI助手。",
    unread_count: 0,
    order_field: 1000,
    ...overrides,
  };
}

// ============ 测试用例 ============

describe("E2E /conversations CRUD", () => {
  it("缺少 X-BFF-Token 返回 401", async () => {
    const env = makeEnv();
    const req = makeRequest("/conversations", { method: "GET" });
    const resp = await worker.fetch(req, env, {});
    expect(resp.status).toBe(401);
  });

  it("POST /conversations 创建会话返回 201 + 完整对象", async () => {
    const env = makeEnv([
      // INSERT 成功
      ["INSERT INTO conversations", { run: () => ({ success: true, changes: 1 }) }],
    ]);
    const req = makeRequest("/conversations", {
      method: "POST",
      token: VALID_TOKEN,
      body: { title: "新会话", systemPrompt: "你是助手" },
    });
    const resp = await worker.fetch(req, env, {});
    expect(resp.status).toBe(201);
    const data = await resp.json();
    expect(data.id).toBeTruthy();
    expect(data.user_id).toBe(USER_ID);
    expect(data.title).toBe("新会话");
    expect(data.system_prompt).toBe("你是助手");
  });

  it("POST /conversations 请求体非法返回 400", async () => {
    const env = makeEnv();
    const req = makeRequest("/conversations", {
      method: "POST",
      token: VALID_TOKEN,
      body: "{bad",
    });
    const resp = await worker.fetch(req, env, {});
    expect(resp.status).toBe(400);
  });

  it("GET /conversations 列出当前用户会话", async () => {
    const rows = [convRow({ id: "c1" }), convRow({ id: "c2", title: "第二个" })];
    const env = makeEnv([
      ["WHERE user_id = ?1 ORDER BY", { all: () => ({ results: rows }) }],
    ]);
    const req = makeRequest("/conversations", { method: "GET", token: VALID_TOKEN });
    const resp = await worker.fetch(req, env, {});
    expect(resp.status).toBe(200);
    const data = await resp.json();
    expect(data.conversations).toHaveLength(2);
    expect(data.conversations.map((c) => c.id)).toEqual(["c1", "c2"]);
  });

  it("GET /conversations/:id 返回单个会话", async () => {
    const row = convRow({ id: "conv-xyz" });
    const env = makeEnv([
      ["WHERE id = ?1 AND user_id", { first: () => row }],
    ]);
    const req = makeRequest("/conversations/conv-xyz", {
      method: "GET",
      token: VALID_TOKEN,
    });
    const resp = await worker.fetch(req, env, {});
    expect(resp.status).toBe(200);
    const data = await resp.json();
    expect(data.conversation.id).toBe("conv-xyz");
  });

  it("GET /conversations/:id 不存在返回 404", async () => {
    const env = makeEnv([
      ["WHERE id = ?1 AND user_id", { first: () => null }],
    ]);
    const req = makeRequest("/conversations/nope", {
      method: "GET",
      token: VALID_TOKEN,
    });
    const resp = await worker.fetch(req, env, {});
    expect(resp.status).toBe(404);
  });

  it("PATCH /conversations/:id 更新标题并返回更新后对象", async () => {
    const updated = convRow({ id: "conv-1", title: "新标题", is_pinned: 1 });
    const env = makeEnv([
      ["UPDATE conversations SET", { run: () => ({ success: true, changes: 1 }) }],
      ["WHERE id = ?1 AND user_id", { first: () => updated }],
    ]);
    const req = makeRequest("/conversations/conv-1", {
      method: "PATCH",
      token: VALID_TOKEN,
      body: { title: "新标题", isPinned: 1 },
    });
    const resp = await worker.fetch(req, env, {});
    expect(resp.status).toBe(200);
    const data = await resp.json();
    expect(data.conversation.title).toBe("新标题");
    expect(data.conversation.is_pinned).toBe(1);
  });

  it("PATCH /conversations/:id 无可更新字段返回 400", async () => {
    const env = makeEnv();
    const req = makeRequest("/conversations/conv-1", {
      method: "PATCH",
      token: VALID_TOKEN,
      body: {},
    });
    const resp = await worker.fetch(req, env, {});
    expect(resp.status).toBe(400);
  });

  it("PATCH /conversations/:id 目标不存在（changes=0）返回 404", async () => {
    const env = makeEnv([
      ["UPDATE conversations SET", { run: () => ({ success: true, changes: 0 }) }],
    ]);
    const req = makeRequest("/conversations/nope", {
      method: "PATCH",
      token: VALID_TOKEN,
      body: { title: "x" },
    });
    const resp = await worker.fetch(req, env, {});
    expect(resp.status).toBe(404);
  });

  it("DELETE /conversations/:id 成功返回 deleted:true", async () => {
    const env = makeEnv([
      ["DELETE FROM messages WHERE conversation_id", { run: () => ({ success: true, changes: 0 }) }],
      ["DELETE FROM conversations WHERE id = ?1 AND user_id", { run: () => ({ success: true, changes: 1 }) }],
    ]);
    const req = makeRequest("/conversations/conv-1", {
      method: "DELETE",
      token: VALID_TOKEN,
    });
    const resp = await worker.fetch(req, env, {});
    expect(resp.status).toBe(200);
    const data = await resp.json();
    expect(data.deleted).toBe(true);
    expect(data.id).toBe("conv-1");
  });

  it("DELETE /conversations/:id 不存在返回 404", async () => {
    const env = makeEnv([
      ["DELETE FROM messages WHERE conversation_id", { run: () => ({ success: true, changes: 0 }) }],
      ["DELETE FROM conversations WHERE id = ?1 AND user_id", { run: () => ({ success: true, changes: 0 }) }],
    ]);
    const req = makeRequest("/conversations/nope", {
      method: "DELETE",
      token: VALID_TOKEN,
    });
    const resp = await worker.fetch(req, env, {});
    expect(resp.status).toBe(404);
  });

  it("GET /conversations 响应 Content-Type 为 application/json", async () => {
    const env = makeEnv([
      ["WHERE user_id = ?1 ORDER BY", { all: () => ({ results: [] }) }],
    ]);
    const req = makeRequest("/conversations", { method: "GET", token: VALID_TOKEN });
    const resp = await worker.fetch(req, env, {});
    expect(resp.headers.get("Content-Type")).toContain("application/json");
    const data = await resp.json();
    expect(Array.isArray(data.conversations)).toBe(true);
  });
});
