/**
 * 健康摘要路由端到端测试
 *
 * 覆盖 POST /health/summary 与 GET /health/summary/:date：
 * 鉴权、日期校验、upsert、envelope 与 snake_case 字段、按 user_id 隔离。
 * KV（bff_tokens）与 D1（DB）均用内存 Mock，不依赖真实 Cloudflare。
 */

import { describe, it, expect } from "vitest";
import worker from "../worker.js";

const VALID_TOKEN = "bff-token-health";
const USER_ID = "user-health-1";

function makeKV() {
  const store = new Map([[VALID_TOKEN, JSON.stringify({ userId: USER_ID })]]);
  return { get: async (key) => (store.has(key) ? store.get(key) : null) };
}

/** D1 mock：记录执行过的 SQL/binds，按 SQL 子字符串匹配返回值 */
function makeDB(pairs = []) {
  const handlers = pairs.map(([match, fns]) => ({ match, ...fns }));
  const statements = [];
  const db = {
    statements,
    prepare(sql) {
      const matched = handlers.find((h) => sql.includes(h.match));
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
  };
  return db;
}

function makeEnv(pairs = []) {
  return { bff_tokens: makeKV(), DB: makeDB(pairs) };
}

function makeRequest(path, { method = "GET", token, body } = {}) {
  const headers = new Headers();
  if (token) headers.set("X-BFF-Token", token);
  const init = { method, headers };
  if (body !== undefined) {
    init.body = JSON.stringify(body);
    headers.set("Content-Type", "application/json");
  }
  return new Request("https://bff.test" + path, init);
}

function healthRow(overrides = {}) {
  return {
    user_id: USER_ID,
    date: "2026-01-01",
    steps: 8000,
    sleep_hours: 7.5,
    resting_heart_rate: 58,
    ...overrides,
  };
}

describe("E2E /health/summary", () => {
  it("缺少 X-BFF-Token 返回 401", async () => {
    const resp = await worker.fetch(
      makeRequest("/health/summary", { method: "POST", body: { date: "2026-01-01" } }),
      makeEnv(),
      {}
    );
    expect(resp.status).toBe(401);
  });

  it("上报成功返回 {summary} 且字段为 snake_case", async () => {
    const env = makeEnv();
    const resp = await worker.fetch(
      makeRequest("/health/summary", {
        method: "POST",
        token: VALID_TOKEN,
        body: { date: "2026-01-01", steps: 8000, sleepHours: 7.5, restingHeartRate: 58 },
      }),
      env,
      {}
    );

    expect(resp.status).toBe(200);
    expect(await resp.json()).toEqual({
      summary: {
        user_id: USER_ID,
        date: "2026-01-01",
        steps: 8000,
        sleep_hours: 7.5,
        resting_heart_rate: 58,
      },
    });

    // upsert 必须按 (user_id, date) 写入，避免跨用户覆盖
    const insert = env.DB.statements.find((s) => s.sql.includes("INSERT OR REPLACE INTO health_summaries"));
    expect(insert).toBeDefined();
    expect(insert.binds).toEqual([USER_ID, "2026-01-01", 8000, 7.5, 58]);
  });

  it("date 格式非法返回 400", async () => {
    const resp = await worker.fetch(
      makeRequest("/health/summary", {
        method: "POST",
        token: VALID_TOKEN,
        body: { date: "2026/01/01" },
      }),
      makeEnv(),
      {}
    );
    expect(resp.status).toBe(400);
  });

  it("GET 返回 {summary} envelope", async () => {
    const env = makeEnv([["FROM health_summaries", { first: () => healthRow() }]]);
    const resp = await worker.fetch(
      makeRequest("/health/summary/2026-01-01", { token: VALID_TOKEN }),
      env,
      {}
    );

    expect(resp.status).toBe(200);
    expect(await resp.json()).toEqual({ summary: healthRow() });
    expect(env.DB.statements[0].binds).toEqual([USER_ID, "2026-01-01"]);
  });

  it("GET 无数据返回 404", async () => {
    const resp = await worker.fetch(
      makeRequest("/health/summary/2026-01-02", { token: VALID_TOKEN }),
      makeEnv(),
      {}
    );
    expect(resp.status).toBe(404);
  });

  it("GET date 格式非法返回 400", async () => {
    const resp = await worker.fetch(
      makeRequest("/health/summary/2026-1-1", { token: VALID_TOKEN }),
      makeEnv(),
      {}
    );
    expect(resp.status).toBe(400);
  });
});
