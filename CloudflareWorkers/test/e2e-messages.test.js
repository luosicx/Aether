/**
 * 消息路由端到端测试（列表 / 删除 / 反馈）
 *
 * 通过 worker.fetch 走完整 鉴权 → 路由分发 → messages handler 链路。
 * 重点回归：D1 .run() 的 changes 位于 result.meta.changes，且删除/更新按 user_id 限定。
 */

import { describe, it, expect } from "vitest";
import worker from "../worker.js";

const VALID_TOKEN = "bff-token-msg";
const USER_ID = "user-msg-1";

function makeKV() {
  const store = new Map();
  store.set(VALID_TOKEN, JSON.stringify({ userId: USER_ID }));
  return { get: async (k) => (store.has(k) ? store.get(k) : null) };
}

/** D1 mock：按 SQL 子字符串匹配注册返回值，并记录语句与绑定参数 */
function makeDB() {
  const handlers = [];
  const statements = [];
  const db = {
    statements,
    prepare(sql) {
      const matched = handlers.find((h) =>
        h.match instanceof RegExp ? h.match.test(sql) : sql.includes(h.match)
      );
      let binds = [];
      const entry = { sql, binds };
      statements.push(entry);
      const stmt = {
        bind(...args) {
          binds = args;
          entry.binds = args;
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
            : { success: true, meta: { changes: 1 } };
        },
      };
      return stmt;
    },
    async batch(stmts) {
      return Promise.all(stmts.map((stmt) => stmt.run()));
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

function makeRequest(path, { method = "GET", token, body } = {}) {
  const h = new Headers();
  if (token) h.set("X-BFF-Token", token);
  const init = { method, headers: h };
  if (body !== undefined) {
    init.body = typeof body === "string" ? body : JSON.stringify(body);
    h.set("Content-Type", "application/json");
  }
  return new Request("https://bff.test" + path, init);
}

describe("E2E /messages", () => {
  it("缺少 X-BFF-Token 返回 401", async () => {
    const env = makeEnv();
    const resp = await worker.fetch(makeRequest("/messages/m1", { method: "DELETE" }), env, {});
    expect(resp.status).toBe(401);
  });

  it("GET 会话消息返回 envelope + snake_case 字段", async () => {
    const rows = [
      {
        id: "m1",
        conversation_id: "c1",
        role: "user",
        content: "你好",
        tool_calls: null,
        tool_call_id: null,
        tool_name: null,
        feedback: 1,
        created_at: 1000,
      },
    ];
    const env = makeEnv([
      ["SELECT id FROM conversations WHERE id = ?1 AND user_id", { first: () => ({ id: "c1" }) }],
      ["FROM messages WHERE conversation_id", { all: () => ({ results: rows }) }],
    ]);
    const resp = await worker.fetch(
      makeRequest("/conversations/c1/messages", { token: VALID_TOKEN }),
      env,
      {}
    );
    expect(resp.status).toBe(200);
    const data = await resp.json();
    expect(data.messages).toHaveLength(1);
    expect(data.messages[0].conversation_id).toBe("c1");
    expect(data.messages[0].feedback).toBe(1);
  });

  it("DELETE 删除成功（meta.changes=1）返回 200，且 SQL 按 user_id 限定", async () => {
    const env = makeEnv([
      ["DELETE FROM messages", { run: () => ({ success: true, meta: { changes: 1 } }) }],
    ]);
    const resp = await worker.fetch(
      makeRequest("/messages/m1", { method: "DELETE", token: VALID_TOKEN }),
      env,
      {}
    );
    expect(resp.status).toBe(200);
    expect((await resp.json()).deleted).toBe(true);

    const stmt = env.DB.statements.find((s) => s.sql.includes("DELETE FROM messages"));
    expect(stmt.sql).toContain("SELECT id FROM conversations WHERE user_id = ?2");
    expect(stmt.binds).toEqual(["m1", USER_ID]);
  });

  it("DELETE 无匹配行（meta.changes=0）返回 404", async () => {
    const env = makeEnv([
      ["DELETE FROM messages", { run: () => ({ success: true, meta: { changes: 0 } }) }],
    ]);
    const resp = await worker.fetch(
      makeRequest("/messages/nope", { method: "DELETE", token: VALID_TOKEN }),
      env,
      {}
    );
    expect(resp.status).toBe(404);
  });

  it("POST 反馈成功（meta.changes=1）返回反馈值", async () => {
    const env = makeEnv([
      ["UPDATE messages SET feedback", { run: () => ({ success: true, meta: { changes: 1 } }) }],
    ]);
    const resp = await worker.fetch(
      makeRequest("/messages/m1/feedback", {
        method: "POST",
        token: VALID_TOKEN,
        body: { feedback: -1 },
      }),
      env,
      {}
    );
    expect(resp.status).toBe(200);
    const data = await resp.json();
    expect(data.id).toBe("m1");
    expect(data.feedback).toBe(-1);

    const stmt = env.DB.statements.find((s) => s.sql.includes("UPDATE messages SET feedback"));
    expect(stmt.binds).toEqual([-1, "m1", USER_ID]);
  });

  it("POST 反馈无匹配行（meta.changes=0）返回 404", async () => {
    const env = makeEnv([
      ["UPDATE messages SET feedback", { run: () => ({ success: true, meta: { changes: 0 } }) }],
    ]);
    const resp = await worker.fetch(
      makeRequest("/messages/nope/feedback", {
        method: "POST",
        token: VALID_TOKEN,
        body: { feedback: 1 },
      }),
      env,
      {}
    );
    expect(resp.status).toBe(404);
  });
});
