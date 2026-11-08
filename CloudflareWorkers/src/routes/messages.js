/**
 * 消息路由：消息列表、删除、反馈
 *
 * 所有端点需要鉴权（X-BFF-Token）。数据访问统一经 ctx.db（tenant-db 访问器），
 * user_id 由访问器绑定，路由层不直接持有 env.DB。
 * 路由函数签名统一 (request, env, ctx)，ctx 可选。
 */

import { jsonError } from "../lib/llm.js";

/**
 * GET /conversations/:conversationId/messages - 列出某会话下的消息
 * query: ?limit=100&offset=0&order=asc
 */
export async function handleListMessages(request, env, ctx, conversationId) {
  if (!ctx || !ctx.auth) return jsonError(401, "未鉴权");
  const db = ctx.db;
  if (!conversationId) return jsonError(400, "缺少 conversationId");
  if (!db) return jsonError(503, "数据库未配置");

  const url = new URL(request.url);
  const limit = Math.min(parseInt(url.searchParams.get("limit") || "100", 10), 500);
  const offset = parseInt(url.searchParams.get("offset") || "0", 10);
  const order = url.searchParams.get("order") === "desc" ? "DESC" : "ASC";

  try {
    // 访问器内部先校验会话归属，非本人会话返回 null
    const messages = await db.listMessages(conversationId, { limit, offset, order });
    if (messages === null) return jsonError(404, "会话不存在或无权访问");
    return jsonOk({ messages });
  } catch (err) {
    return jsonError(500, "查询消息失败: " + (err && err.message));
  }
}

/**
 * DELETE /messages/:messageId - 删除单条消息
 */
export async function handleDeleteMessage(request, env, ctx, messageId) {
  if (!ctx || !ctx.auth) return jsonError(401, "未鉴权");
  const db = ctx.db;
  if (!messageId) return jsonError(400, "缺少 messageId");
  if (!db) return jsonError(503, "数据库未配置");

  try {
    const deleted = await db.deleteMessage(messageId);
    if (!deleted) return jsonError(404, "消息不存在或无权删除");
    return jsonOk({ deleted: true, id: messageId });
  } catch (err) {
    return jsonError(500, "删除消息失败: " + (err && err.message));
  }
}

/**
 * POST /messages/:messageId/feedback - 对消息反馈（点赞/点踩）
 * body: { feedback: 1 | -1 | 0 }
 */
export async function handleSubmitFeedback(request, env, ctx, messageId) {
  if (!ctx || !ctx.auth) return jsonError(401, "未鉴权");
  const db = ctx.db;
  if (!messageId) return jsonError(400, "缺少 messageId");
  if (!db) return jsonError(503, "数据库未配置");

  let body;
  try {
    body = await request.json();
  } catch (_) {
    return jsonError(400, "请求体不是合法 JSON");
  }

  const fb = body && body.feedback;
  let feedbackValue;
  if (fb === 1 || fb === -1) {
    feedbackValue = fb;
  } else if (fb === 0) {
    feedbackValue = null; // 取消反馈
  } else {
    return jsonError(400, "feedback 必须为 1 / -1 / 0");
  }

  try {
    const changed = await db.setMessageFeedback(messageId, feedbackValue);
    if (!changed) return jsonError(404, "消息不存在或无权操作");
    return jsonOk({ id: messageId, feedback: feedbackValue });
  } catch (err) {
    console.error("反馈失败:", err && err.message);
    return jsonError(500, "反馈失败");
  }
}

/// 构造 JSON 成功响应
function jsonOk(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
