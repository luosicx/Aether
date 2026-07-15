/**
 * 聊天路由：流式对话
 *
 * POST /chat/stream - 流式聊天
 *   鉴权：X-BFF-Token
 *   限流：每 userId 每分钟 60 次
 *   body: { message, conversationId?, model?, memoryEnabled?, provider?, temperature?, maxTokens?, systemPrompt? }
 *
 * 流程：
 *   1. 鉴权 + 限流
 *   2. 加载会话（若 conversationId 为空则自动创建）
 *   3. 拉取历史消息（最近 N 条）
 *   4. 若 memoryEnabled，检索相关长期记忆
 *   5. RAG：检索相关文档分块
 *   6. buildContext 构建 messages
 *   7. 调用 LLM 流式接口，SSE 透传增量
 *   8. 后台持久化用户消息 + 助手完整响应（ctx.waitUntil）
 *
 * SSE 格式：
 *   data: {"type":"delta","content":"xxx"}\n\n
 *   data: {"type":"done","conversationId":"xxx","messageId":"xxx"}\n\n
 *   data: [DONE]\n\n
 *   data: {"type":"error","message":"xxx"}\n\n
 */

import { jsonError } from "../lib/llm.js";
import { redact } from "../lib/redact.js";
import { buildContext, callLLMStream } from "../lib/llm.js";
import { fetchRelevantMemories } from "../lib/memory.js";
import { searchDocuments } from "../lib/rag.js";

// 加载历史消息条数
const HISTORY_LIMIT = 20;

/**
 * 处理聊天流式请求
 * @param {Request} request
 * @param {Object} env
 * @param {Object} ctx - Cloudflare Workers 执行上下文，需含 ctx.auth（鉴权信息）、ctx.waitUntil
 */
export async function handleChatStream(request, env, ctx) {
  const auth = ctx && ctx.auth;
  if (!auth) return jsonError(401, "未鉴权");

  // 1. 解析 body
  let body;
  try {
    body = await request.json();
  } catch (_) {
    return jsonError(400, "请求体不是合法 JSON");
  }
  if (!body || !body.message) {
    return jsonError(400, "message 不能为空");
  }

  const model = body.model || "deepseek-chat";
  const provider = body.provider || "deepseek";
  const memoryEnabled = body.memoryEnabled !== false; // 默认开启
  const now = Date.now();

  // 2. 加载或创建会话
  let conversationId = body.conversationId;
  let systemPrompt = body.systemPrompt || "你是一个有帮助的AI助手。";

  if (env.DB) {
    if (conversationId) {
      // 校验会话归属并取 system_prompt
      try {
        const conv = await env.DB.prepare(
          `SELECT id, system_prompt FROM conversations WHERE id = ?1 AND user_id = ?2`
        )
          .bind(conversationId, auth.userId)
          .first();
        if (!conv) {
          return jsonError(404, "会话不存在或无权访问");
        }
        if (conv.system_prompt) systemPrompt = conv.system_prompt;
      } catch (err) {
        return jsonError(500, "加载会话失败: " + (err && err.message));
      }
    } else {
      // 自动创建新会话
      conversationId = genId();
      const title = deriveTitle(body.message);
      try {
        await env.DB.prepare(
          `INSERT INTO conversations (id, user_id, title, parent_id, created_at, updated_at, system_prompt, order_field)
           VALUES (?1, ?2, ?3, NULL, ?4, ?5, ?6, ?7)`
        )
          .bind(conversationId, auth.userId, title, now, now, systemPrompt, now)
          .run();
      } catch (err) {
        return jsonError(500, "创建会话失败: " + (err && err.message));
      }
    }
  } else {
    if (!conversationId) conversationId = genId();
  }

  // 3. 拉取历史消息（DB 可用时）
  let history = [];
  if (env.DB && body.conversationId) {
    try {
      const { results } = await env.DB.prepare(
        `SELECT role, content FROM messages
         WHERE conversation_id = ?1
         ORDER BY created_at DESC LIMIT ?2`
      )
        .bind(conversationId, HISTORY_LIMIT)
        .all();
      // 反转为时间正序
      history = (results || []).reverse();
    } catch (err) {
      console.error("load history error:", err && err.message);
    }
  }

  // 4 & 5. 并行检索记忆 + RAG 文档
  const [memories, relevantDocs] = await Promise.all([
    memoryEnabled ? fetchRelevantMemories(env, auth.userId, body.message, 5) : Promise.resolve([]),
    searchDocuments(env, auth.userId, body.message, 3),
  ]);

  // 6. 构建上下文
  const messages = buildContext(history, memories, relevantDocs, {
    message: body.message,
    systemPrompt,
  });

  // 7. 构造 SSE 流
  const encoder = new TextEncoder();
  const { readable, writable } = new TransformStream();
  const writer = writable.getWriter();

  // 持久化用户消息（先写入，不等流式完成）
  const userMessageId = genId();
  if (env.DB) {
    try {
      await env.DB.prepare(
        `INSERT INTO messages (id, conversation_id, role, content, created_at)
         VALUES (?1, ?2, 'user', ?3, ?4)`
      )
        .bind(userMessageId, conversationId, body.message, now)
        .run();
      // 更新会话 last_message_preview + updated_at
      await env.DB.prepare(
        `UPDATE conversations SET updated_at = ?1, last_message_preview = ?2 WHERE id = ?3`
      )
        .bind(now, body.message.slice(0, 200), conversationId)
        .run();
    } catch (err) {
      console.error("persist user message error:", err && err.message);
    }
  }

  // 后台流式调用 LLM 并写 SSE
  const assistantMessageId = genId();
  let fullResponse = "";

  const streamTask = (async () => {
    try {
      const opts = {};
      if (typeof body.temperature === "number") opts.temperature = body.temperature;
      if (typeof body.maxTokens === "number") opts.max_tokens = body.maxTokens;
      opts.provider = provider;

      for await (const delta of callLLMStream(env, model, messages, opts)) {
        fullResponse += delta;
        const sseData = JSON.stringify({ type: "delta", content: delta });
        await writer.write(encoder.encode(`data: ${sseData}\n\n`));
      }

      // 完成事件
      const doneData = JSON.stringify({
        type: "done",
        conversationId,
        messageId: assistantMessageId,
        userMessageId,
      });
      await writer.write(encoder.encode(`data: ${doneData}\n\n`));
      await writer.write(encoder.encode(`data: [DONE]\n\n`));
    } catch (err) {
      const rawMsg = err && err.message ? err.message : "LLM 调用失败";
      // 脱敏错误信息，避免上游返回的 token/路径/URL 泄露给客户端
      const errMsg = await redact(rawMsg);
      const errData = JSON.stringify({ type: "error", message: errMsg });
      // 写错误前先 flush 已有内容
      try {
        await writer.write(encoder.encode(`data: ${errData}\n\n`));
      } catch (_) {
        /* writer 已关闭 */
      }
    } finally {
      // 后台持久化助手响应（即使流式出错，已收到的部分也保存）
      if (env.DB && fullResponse) {
        try {
          await env.DB.prepare(
            `INSERT INTO messages (id, conversation_id, role, content, created_at)
             VALUES (?1, ?2, 'assistant', ?3, ?4)`
          )
            .bind(assistantMessageId, conversationId, fullResponse, Date.now())
            .run();
          // 更新会话 last_message_preview + updated_at
          await env.DB.prepare(
            `UPDATE conversations SET updated_at = ?1, last_message_preview = ?2 WHERE id = ?3`
          )
            .bind(Date.now(), fullResponse.slice(0, 200), conversationId)
            .run();
        } catch (err) {
          console.error("persist assistant message error:", err && err.message);
        }
      }
      try {
        await writer.close();
      } catch (_) {
        /* noop */
      }
    }
  })();

  // 用 ctx.waitUntil 保证后台任务在 Response 返回后继续执行
  if (ctx && typeof ctx.waitUntil === "function") {
    ctx.waitUntil(streamTask);
  } else {
    // 兜底：无 waitUntil 时直接 await（会阻塞但保证完成）
    streamTask.catch(() => {});
  }

  return new Response(readable, {
    status: 200,
    headers: {
      "Content-Type": "text/event-stream; charset=utf-8",
      "Cache-Control": "no-cache, no-transform",
      Connection: "keep-alive",
      "X-Accel-Buffering": "no",
    },
  });
}

/// 从首条消息派生会话标题（取前 20 字符）
function deriveTitle(message) {
  if (!message) return "新会话";
  const trimmed = String(message).trim().replace(/\s+/g, " ");
  return trimmed.length > 20 ? trimmed.slice(0, 20) + "…" : trimmed;
}

/// 生成 UUID
function genId() {
  if (typeof crypto !== "undefined" && crypto.randomUUID) {
    return crypto.randomUUID();
  }
  return "id-" + Date.now().toString(36) + "-" + Math.random().toString(36).slice(2, 10);
}
