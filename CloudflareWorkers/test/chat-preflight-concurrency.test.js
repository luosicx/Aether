/**
 * chat 路由首字前预取并发测试
 *
 * 历史消息 / 长期记忆 / RAG 分块互不依赖，必须在同一 Promise.all 中并行发起，
 * 否则首字前会多出 2 次串行 D1 往返。这里用可控 gate 的假 DB 观察调用时序：
 * 三项都 start 之后才允许任何一项 resolve。
 */

import { describe, it, expect, vi } from "vitest";

const captured = vi.hoisted(() => ({ llmMessages: null }));

vi.mock("../src/lib/llm.js", async (importActual) => {
  const actual = await importActual();
  return {
    ...actual,
    callLLMStream: async function* (_env, _model, messages) {
      captured.llmMessages = messages;
      yield "ok";
    },
  };
});

vi.mock("../src/lib/redact.js", () => ({
  redact: async (s) => (s == null ? "" : String(s)),
}));

import { handleChatStream } from "../src/routes/chat.js";

/** 假 DB：预取方法挂起直到 releaseAll()，期间记录 start / end 顺序 */
function makeGatedDb() {
  const timeline = [];
  const pending = [];
  const gate = (name, result) => {
    timeline.push(`start:${name}`);
    return new Promise((resolve) => {
      pending.push(() => {
        timeline.push(`end:${name}`);
        resolve(result);
      });
    });
  };
  return {
    timeline,
    releaseAll() {
      while (pending.length > 0) pending.shift()();
    },
    getConversationPrompt: async () => ({ id: "c1", system_prompt: "sys" }),
    loadHistory: () => gate("history", [{ role: "user", content: "旧消息" }]),
    searchMemories: () => gate("memories", [{ content: "记忆" }]),
    searchChunks: () => gate("chunks", [{ content: "分块" }]),
    appendUserMessage: async () => "um1",
    appendAssistantMessage: async () => {},
    createConversation: async () => ({ id: "c1" }),
  };
}

function makeCtx(db) {
  const pending = [];
  return {
    auth: { userId: "u1" },
    db,
    waitUntil: (p) => pending.push(Promise.resolve(p).catch(() => {})),
    _pending: pending,
  };
}

function makeRequest(body) {
  return new Request("https://bff.test/chat/stream", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
}

describe("handleChatStream 预取并发", () => {
  it("历史 / 记忆 / RAG 三项在任一 resolve 前全部发起", async () => {
    const db = makeGatedDb();
    const ctx = makeCtx(db);

    const responsePromise = handleChatStream(makeRequest({ message: "hi", conversationId: "c1" }), {}, ctx);

    // 预取已挂起：此时三项都应已 start
    await new Promise((resolve) => setTimeout(resolve, 0));
    expect(db.timeline.filter((t) => t.startsWith("start:"))).toEqual([
      "start:history",
      "start:memories",
      "start:chunks",
    ]);
    expect(db.timeline.filter((t) => t.startsWith("end:"))).toEqual([]);

    db.releaseAll();
    const response = await responsePromise;
    expect(response.status).toBe(200);
    const text = await response.text();
    await Promise.all(ctx._pending);

    // 三项仍在同一批里完成，历史内容参与上下文构建
    for (const name of ["history", "memories", "chunks"]) {
      expect(db.timeline).toContain(`end:${name}`);
    }
    expect(text).toContain("ok");
    expect(JSON.stringify(captured.llmMessages)).toContain("旧消息");
  });

  it("无 conversationId 时跳过历史查询，但仍并行检索记忆与 RAG", async () => {
    const db = makeGatedDb();
    const ctx = makeCtx(db);

    const responsePromise = handleChatStream(makeRequest({ message: "hi", provider: "deepseek" }), {}, ctx);
    await new Promise((resolve) => setTimeout(resolve, 0));

    expect(db.timeline).not.toContain("start:history");
    expect(db.timeline).toContain("start:memories");
    expect(db.timeline).toContain("start:chunks");

    db.releaseAll();
    const response = await responsePromise;
    expect(response.status).toBe(200);
    await response.text();
    await Promise.all(ctx._pending);
  });
});
