/**
 * conversations.js 删除会话路由的安全测试
 *
 * 重点覆盖：跨用户 IDOR 场景——用户 A 不得删除用户 B 的会话消息。
 * 使用内存 mock D1，模拟 prepare/bind/first/run/all 行为。
 */
import { describe, it, expect, beforeEach } from "vitest";
import { handleDeleteConversation } from "../src/routes/conversations.js";

/**
 * 极简内存 D1 mock：
 * - prepare(sql) 返回 { bind(...args), first(), run(), all() }
 * - 仅实现 SELECT / DELETE 的最小语义，足以验证越权防护
 */
function createMockD1(tables) {
  // tables: { conversations: [...], messages: [...] }
  const db = {
    _tables: tables,
    prepare(sql) {
      const self = {
        _binds: [],
        bind(...args) {
          self._binds = args;
          return self;
        },
        async first() {
          return self._execSelect(true);
        },
        async run() {
          return self._execMutation();
        },
        async all() {
          return { results: self._execSelect(false) || [] };
        },
        _execSelect(firstOnly) {
          const upper = sql.toUpperCase().trim();
          if (upper.startsWith("SELECT")) {
            // 简化：按 ?1=? 匹配 conversations 行
            // SELECT id FROM conversations WHERE id = ?1 AND user_id = ?2
            const rows = db._tables.conversations.filter(
              (r) => r.id === self._binds[0] && r.user_id === self._binds[1]
            );
            return firstOnly ? rows[0] || null : rows;
          }
          return null;
        },
        _execMutation() {
          const upper = sql.toUpperCase().trim();
          if (upper.startsWith("DELETE FROM MESSAGES")) {
            // DELETE FROM messages WHERE conversation_id = ?1
            const before = db._tables.messages.length;
            db._tables.messages = db._tables.messages.filter(
              (m) => m.conversation_id !== self._binds[0]
            );
            return { changes: before - db._tables.messages.length };
          }
          if (upper.startsWith("DELETE FROM CONVERSATIONS")) {
            // DELETE FROM conversations WHERE id = ?1 AND user_id = ?2
            const before = db._tables.conversations.length;
            db._tables.conversations = db._tables.conversations.filter(
              (r) => !(r.id === self._binds[0] && r.user_id === self._binds[1])
            );
            return { changes: before - db._tables.conversations.length };
          }
          return { changes: 0 };
        },
      };
      return self;
    },
  };
  return db;
}

function makeRequest() {
  return new Request("https://example.com/conversations/conv-1", {
    method: "DELETE",
  });
}

describe("handleDeleteConversation - IDOR 防护", () => {
  let tables;

  beforeEach(() => {
    tables = {
      conversations: [
        { id: "conv-1", user_id: "userA", title: "A 的会话" },
        { id: "conv-2", user_id: "userB", title: "B 的会话" },
      ],
      messages: [
        { id: "msg-1", conversation_id: "conv-1", role: "user", content: "hi A" },
        { id: "msg-2", conversation_id: "conv-1", role: "assistant", content: "hello A" },
        { id: "msg-3", conversation_id: "conv-2", role: "user", content: "hi B" },
        { id: "msg-4", conversation_id: "conv-2", role: "assistant", content: "hello B" },
      ],
    };
  });

  it("用户删除自己的会话时，消息和会话均被删除", async () => {
    const env = { DB: createMockD1(tables) };
    const ctx = { auth: { userId: "userA", user: null } };

    const resp = await handleDeleteConversation(makeRequest(), env, ctx, "conv-1");
    const body = await resp.json();

    expect(resp.status).toBe(200);
    expect(body.deleted).toBe(true);
    // conv-1 的消息被删除
    expect(tables.messages.filter((m) => m.conversation_id === "conv-1")).toHaveLength(0);
    // conv-1 会话被删除
    expect(tables.conversations.filter((c) => c.id === "conv-1")).toHaveLength(0);
  });

  it("用户 A 删除用户 B 的会话时，不得删除 B 的消息（IDOR 防护）", async () => {
    const env = { DB: createMockD1(tables) };
    const ctx = { auth: { userId: "userA", user: null } };

    // userA 尝试删除 userB 的会话 conv-2
    const resp = await handleDeleteConversation(makeRequest(), env, ctx, "conv-2");
    const body = await resp.json();

    // 应返回 404，而非删除
    expect(resp.status).toBe(404);
    // 关键断言：userB 的消息不得被删除
    expect(tables.messages.filter((m) => m.conversation_id === "conv-2")).toHaveLength(2);
    // userB 的会话仍然存在
    expect(tables.conversations.filter((c) => c.id === "conv-2")).toHaveLength(1);
  });

  it("删除不存在的会话返回 404", async () => {
    const env = { DB: createMockD1(tables) };
    const ctx = { auth: { userId: "userA", user: null } };

    const resp = await handleDeleteConversation(makeRequest(), env, ctx, "nonexistent");
    expect(resp.status).toBe(404);
  });
});
