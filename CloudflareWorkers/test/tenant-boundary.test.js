/**
 * 租户边界测试
 *
 * 两条防线：
 * 1. 静态：路由层不得持有 env.DB / 拼 SQL，所有数据访问必须经 tenant-db
 * 2. 动态：tenant-db 的每条语句都带租户约束，多语句写走 batch
 *
 * 防回归点：任何新增路由若绕过 ctx.db 直连 D1，或新 SQL 漏写 user_id，都会在此失败。
 */

import { describe, it, expect } from "vitest";
import { readFileSync, readdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { createTenantDB } from "../src/lib/tenant-db.js";
import worker from "../worker.js";

const HERE = dirname(fileURLToPath(import.meta.url));
const ROUTES_DIR = join(HERE, "../src/routes");
const USER_ID = "tenant-user-a";

/** 记录 prepare / batch 的假 D1；first 返回一条行，便于覆盖"查到后继续"的分支 */
function makeRecordingDB() {
  const statements = [];
  const batches = [];

  const prepare = (sql) => {
    const entry = { sql, binds: [] };
    statements.push(entry);
    const stmt = {
      sql,
      bind(...args) {
        entry.binds = args;
        return stmt;
      },
      async first() {
        return { id: "conv-1" };
      },
      async all() {
        return { results: [] };
      },
      async run() {
        return { success: true, meta: { changes: 1 } };
      },
    };
    return stmt;
  };

  return {
    statements,
    batches,
    prepare,
    async batch(stmts) {
      batches.push(stmts);
      return stmts.map(() => ({ success: true, meta: { changes: 1 } }));
    },
  };
}

/** 需要覆盖的租户访问器调用（每个方法至少触发一条语句） */
const CALLS = [
  ["listConversations", (db) => db.listConversations()],
  ["listConversations(pinned)", (db) => db.listConversations({ pinnedOnly: true })],
  ["createConversation", (db) => db.createConversation({ title: "t" })],
  ["getConversation", (db) => db.getConversation("conv-1")],
  ["updateConversation", (db) => db.updateConversation("conv-1", { title: "x" })],
  ["deleteConversation", (db) => db.deleteConversation("conv-1")],
  ["listMessages", (db) => db.listMessages("conv-1", { limit: 10, offset: 0, order: "ASC" })],
  ["deleteMessage", (db) => db.deleteMessage("m1")],
  ["setMessageFeedback", (db) => db.setMessageFeedback("m1", 1)],
  ["listMemories", (db) => db.listMemories()],
  ["listMemories(category)", (db) => db.listMemories({ category: "pref" })],
  ["createMemory", (db) => db.createMemory({ content: "c" })],
  ["searchMemories", (db) => db.searchMemories("c")],
  ["deleteMemory", (db) => db.deleteMemory("m1")],
  ["searchChunks", (db) => db.searchChunks("c")],
  ["createDocumentWithChunks", (db) => db.createDocumentWithChunks({ content: "hello world" })],
  ["upsertHealthSummary", (db) => db.upsertHealthSummary("2026-01-01", { steps: 1 })],
  ["getHealthSummary", (db) => db.getHealthSummary("2026-01-01")],
  ["getConversationPrompt", (db) => db.getConversationPrompt("conv-1")],
  ["loadHistory", (db) => db.loadHistory("conv-1", 5)],
  ["appendUserMessage", (db) => db.appendUserMessage("conv-1", "hi")],
  ["appendAssistantMessage", (db) => db.appendAssistantMessage("conv-1", "yo")],
];

/** 根租户表：必须自带 user_id 条件 */
const ROOT_TABLES = ["conversations", "memories", "documents", "health_summaries"];
/** 子表：读/改/删必须通过父表限定归属 */
const CHILD_TABLES = ["messages", "document_chunks"];

/** 语句的主表（DML 目标优先，其次 SELECT 的 FROM 表） */
function tableOf(sql) {
  const insert = sql.match(/\bINSERT\s+(?:OR\s+\w+\s+)?INTO\s+(\w+)/i);
  if (insert) return insert[1];
  const update = sql.match(/\bUPDATE\s+(\w+)/i);
  if (update) return update[1];
  const del = sql.match(/\bDELETE\s+FROM\s+(\w+)/i);
  if (del) return del[1];
  const select = sql.match(/\bFROM\s+(\w+)/i);
  return select ? select[1] : null;
}

describe("租户边界静态约束", () => {
  const routeFiles = readdirSync(ROUTES_DIR).filter((f) => f.endsWith(".js"));

  it("存在待检查的路由文件", () => {
    expect(routeFiles.length).toBeGreaterThan(0);
  });

  it("路由层不使用 env.DB、不拼 SQL（只能经 ctx.db）", () => {
    const offenders = [];
    for (const file of routeFiles) {
      const raw = readFileSync(join(ROUTES_DIR, file), "utf8");
      // 去掉注释，避免文档里提到 env.DB 被误判
      const code = raw
        .replace(/\/\*[\s\S]*?\*\//g, "")
        .replace(/^\s*\/\/.*$/gm, "");
      if (/env\s*\.\s*DB/.test(code)) offenders.push(file + ": env.DB");
      if (/\.prepare\s*\(|\.batch\s*\(/.test(code)) offenders.push(file + ": raw SQL");
    }
    expect(offenders).toEqual([]);
  });
});

describe("createTenantDB 构造", () => {
  it("缺少 DB 或 userId 时返回 null", () => {
    expect(createTenantDB({}, USER_ID)).toBeNull();
    expect(createTenantDB({ DB: {} }, "")).toBeNull();
    expect(createTenantDB(null, USER_ID)).toBeNull();
  });

  it("正常构造返回访问器", () => {
    const db = createTenantDB({ DB: makeRecordingDB() }, USER_ID);
    expect(db).not.toBeNull();
  });
});

describe("租户边界 SQL 约束", () => {
  const recorded = [];
  for (const [name, call] of CALLS) {
    const DB = makeRecordingDB();
    const db = createTenantDB({ DB }, USER_ID);
    // 每个方法单独记录，便于失败时定位
    recorded.push(
      Promise.resolve()
        .then(() => call(db))
        .then(() => ({ name, DB }))
    );
  }

  it("所有根表语句都绑定 user_id 与当前用户", async () => {
    const results = await Promise.all(recorded);
    const violations = [];
    for (const { name, DB } of results) {
      for (const { sql, binds } of DB.statements) {
        const table = tableOf(sql);
        if (!ROOT_TABLES.includes(table)) continue;
        if (!/user_id/.test(sql)) {
          violations.push(`${name}: 缺少 user_id 条件 -> ${sql.replace(/\s+/g, " ")}`);
        }
        if (!binds.includes(USER_ID)) {
          violations.push(`${name}: 未绑定当前 userId -> ${sql.replace(/\s+/g, " ")}`);
        }
      }
    }
    expect(violations).toEqual([]);
  });

  it("子表读/改/删通过父表限定归属", async () => {
    const results = await Promise.all(recorded);
    const violations = [];
    for (const { name, DB } of results) {
      for (const { sql } of DB.statements) {
        const table = tableOf(sql);
        if (!CHILD_TABLES.includes(table)) continue;
        const isReadWrite = /^\s*(SELECT|UPDATE|DELETE)\b/i.test(sql);
        if (!isReadWrite) continue; // INSERT 由父行 id 关联，另见 batch 断言
        if (!/conversations|documents/.test(sql)) {
          violations.push(`${name}: 子表查询未限定父表归属 -> ${sql.replace(/\s+/g, " ")}`);
        }
      }
    }
    expect(violations).toEqual([]);
  });

  it("多语句写操作走 DB.batch（单事务）", async () => {
    const results = await Promise.all(recorded);
    const byName = Object.fromEntries(results.map((r) => [r.name, r.DB]));

    for (const name of [
      "deleteConversation",
      "appendUserMessage",
      "appendAssistantMessage",
      "createDocumentWithChunks",
    ]) {
      expect(byName[name].batches.length, `${name} 应使用 batch`).toBeGreaterThan(0);
      for (const stmts of byName[name].batches) {
        expect(stmts.length).toBeGreaterThan(1);
      }
    }
  });

  it("文档与其分块在同一 batch 中写入，且文档行绑定 user_id", async () => {
    const DB = makeRecordingDB();
    const db = createTenantDB({ DB }, USER_ID);
    const result = await db.createDocumentWithChunks({ content: "hello world" });
    expect(result).not.toBeNull();

    const [stmts] = DB.batches;
    expect(stmts[0].sql).toContain("INTO documents");
    const documentsEntry = DB.statements.find((s) => tableOf(s.sql) === "documents");
    expect(documentsEntry.binds).toContain(USER_ID);
    expect(stmts.length).toBe(result.chunkCount + 1);
  });
});

describe("跨租户访问（worker 端到端）", () => {
  const ATTACKER_TOKEN = "tenant-token-attacker";
  const VICTIM_CONV = "victim-conv";
  const VICTIM_USER = "tenant-user-victim";

  /** KV：攻击者 token → 攻击者 userId */
  function makeEnv() {
    const store = new Map([[ATTACKER_TOKEN, JSON.stringify({ userId: USER_ID })]]);
    const statements = [];
    // 语义化 D1：只有 user_id 条件命中受害者的查询才能读到数据
    const DB = {
      statements,
      prepare(sql) {
        const entry = { sql, binds: [] };
        statements.push(entry);
        const stmt = {
          bind(...args) {
            entry.binds = args;
            return stmt;
          },
          async first() {
            return entry.binds.includes(VICTIM_USER) ? { id: VICTIM_CONV, title: "受害者会话" } : null;
          },
          async all() {
            return { results: [] };
          },
          async run() {
            return { success: true, meta: { changes: entry.binds.includes(VICTIM_USER) ? 1 : 0 } };
          },
        };
        return stmt;
      },
      async batch(stmts) {
        return Promise.all(stmts.map((s) => s.run()));
      },
    };
    return {
      bff_tokens: { get: async (k) => (store.has(k) ? store.get(k) : null) },
      DB,
    };
  }

  function request(path, method = "GET") {
    return new Request("https://bff.test" + path, {
      method,
      headers: { "X-BFF-Token": ATTACKER_TOKEN },
    });
  }

  it("读取他人会话返回 404", async () => {
    const resp = await worker.fetch(request("/conversations/" + VICTIM_CONV), makeEnv(), {});
    expect(resp.status).toBe(404);
  });

  it("删除他人会话返回 404，且消息删除同样带 user_id 过滤", async () => {
    const env = makeEnv();
    const resp = await worker.fetch(
      request("/conversations/" + VICTIM_CONV, "DELETE"),
      env,
      {}
    );
    expect(resp.status).toBe(404);
    const msgDelete = env.DB.statements.find((s) => s.sql.includes("DELETE FROM messages"));
    expect(msgDelete).toBeDefined();
    expect(msgDelete.binds).toContain(USER_ID);
  });

  it("查询他人健康摘要返回 404", async () => {
    const env = makeEnv();
    const resp = await worker.fetch(request("/health/summary/2026-01-01"), env, {});
    expect(resp.status).toBe(404);
    const stmt = env.DB.statements.find((s) => s.sql.includes("FROM health_summaries"));
    expect(stmt.binds).toEqual([USER_ID, "2026-01-01"]);
  });
});
