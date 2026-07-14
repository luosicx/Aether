/**
 * 消息路由：消息列表、删除、反馈
 *
 * 所有端点需要鉴权（X-BFF-Token）。
 * 路由函数签名统一 (request, env, ctx)，ctx 可选。
 */

import { jsonError } from "../lib/llm.js";

/**
 * GET /conversations/:conversationId/messages - 列出某会话下的消息
 * query: ?limit=100&offset=0&order=asc
 */
export async function handleListMessages(request, env, ctx, conversationId) {
  const auth = ctx && ctx.auth;
  if (!auth) return jsonError(401, "未鉴权");
  if (!conversationId) return jsonError(400, "缺少 conversationId");
  if (!env.DB) return jsonError(503, "数据库未配置");

  const url = new URL(request.url);
  const limit = Math.min(parseInt(url.searchParams.get("limit") || "100", 10), 500);
  const offset = parseInt(url.searchParams.get("offset") || "0", 10);
  const order = url.searchParams.get("order") === "desc" ? "DESC" : "ASC";

  // 先校验该会话属于当前用户，避免越权读取
  try {
    const conv = await env.DB.prepare(
      `SELECT id FROM conversations WHERE id = ?1 AND user_id = ?2`
    )
      .bind(conversationId, auth.userId)
      .first();
    if (!conv) return jsonError(404, "会话不存在或无权访问");

    const { results } = await env.DB.prepare(
      `SELECT * FROM messages WHERE conversation_id = ?1 ORDER BY created_at ${order} LIMIT ?2 OFFSET ?3`
    )
      .bind(conversationId, limit, offset)
      .all();
    return jsonOk({ messages: results || [] });
  } catch (err) {
    return jsonError(500, "查询消息失败: " + (err && err.message));
  }
}

/**
 * DELETE /messages/:messageId - 删除单条消息
 */
export async function handleDeleteMessage(request, env, ctx, messageId) {
  const auth = ctx && ctx.auth;
  if (!auth) return jsonError(401, "未鉴权");
  if (!messageId) return jsonError(400, "缺少 messageId");
  if (!env.DB) return jsonError(503, "数据库未配置");

  try {
    // 通过 JOIN 校验消息所属会话属于当前用户
    const { changes } = await env.DB.prepare(
      `DELETE FROM messages
       WHERE id = ?1 AND conversation_id IN (
         SELECT id FROM conversations WHERE user_id = ?2
       )`
    )
      .bind(messageId, auth.userId)
      .run();
    if (changes === 0) return jsonError(404, "消息不存在或无权删除");
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
  const auth = ctx && ctx.auth;
  if (!auth) return jsonError(401, "未鉴权");
  if (!messageId) return jsonError(400, "缺少 messageId");
  if (!env.DB) return jsonError(503, "数据库未配置");

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
    const { changes } = await env.DB.prepare(
      `UPDATE messages SET feedback = ?1
       WHERE id = ?2 AND conversation_id IN (
         SELECT id FROM conversations WHERE user_id = ?3
       )`
    )
      .bind(feedbackValue, messageId, auth.userId)
      .run();
    if (changes === 0) return jsonError(404, "消息不存在或无权操作");
    return jsonOk({ id: messageId, feedback: feedbackValue });
  } catch (err) {
    return jsonError(500, "反馈失败: " + (err && err.message));
  }
}

/// 构造 JSON 成功响应
function jsonOk(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
