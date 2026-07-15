/**
 * 会话路由：会话的增删改查
 *
 * 所有端点需要鉴权（X-BFF-Token），数据按 user_id 隔离。
 * 路由函数签名统一 (request, env, ctx)，ctx 可选。
 */

import { jsonError } from "../lib/llm.js";

/**
 * GET /conversations - 列出当前用户的会话
 * 支持 query: ?limit=50&offset=0&pinned=1
 */
export async function handleListConversations(request, env, ctx) {
  const auth = ctx && ctx.auth;
  if (!auth) return jsonError(401, "未鉴权");

  const url = new URL(request.url);
  const limit = Math.min(parseInt(url.searchParams.get("limit") || "50", 10), 200);
  const offset = parseInt(url.searchParams.get("offset") || "0", 10);
  const pinnedOnly = url.searchParams.get("pinned") === "1";

  if (!env.DB) return jsonError(503, "数据库未配置");

  try {
    const sql = pinnedOnly
      ? `SELECT * FROM conversations WHERE user_id = ?1 AND is_pinned = 1 ORDER BY is_pinned DESC, updated_at DESC LIMIT ?2 OFFSET ?3`
      : `SELECT * FROM conversations WHERE user_id = ?1 ORDER BY is_pinned DESC, updated_at DESC LIMIT ?2 OFFSET ?3`;
    const { results } = await env.DB.prepare(sql)
      .bind(auth.userId, limit, offset)
      .all();
    return jsonOk({ conversations: results || [] });
  } catch (err) {
    return jsonError(500, "查询会话失败: " + (err && err.message));
  }
}

/**
 * POST /conversations - 创建会话
 * body: { title?, systemPrompt?, parentId? }
 */
export async function handleCreateConversation(request, env, ctx) {
  const auth = ctx && ctx.auth;
  if (!auth) return jsonError(401, "未鉴权");

  let body;
  try {
    body = await request.json();
  } catch (_) {
    return jsonError(400, "请求体不是合法 JSON");
  }

  const now = Date.now();
  const id = genId();
  const title = (body && body.title) || "新会话";
  const systemPrompt = (body && body.systemPrompt) || "你是一个有帮助的AI助手。";
  const parentId = body && body.parentId ? body.parentId : null;

  if (!env.DB) return jsonError(503, "数据库未配置");

  try {
    await env.DB.prepare(
      `INSERT INTO conversations (id, user_id, title, parent_id, created_at, updated_at, system_prompt, order_field)
       VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)`
    )
      .bind(id, auth.userId, title, parentId, now, now, systemPrompt, now)
      .run();

    const conv = {
      id,
      user_id: auth.userId,
      title,
      parent_id: parentId,
      created_at: now,
      updated_at: now,
      last_message_preview: null,
      is_pinned: 0,
      system_prompt: systemPrompt,
      unread_count: 0,
      order_field: now,
    };
    return jsonOk(conv, 201);
  } catch (err) {
    return jsonError(500, "创建会话失败: " + (err && err.message));
  }
}

/**
 * GET /conversations/:id - 获取单个会话
 */
export async function handleGetConversation(request, env, ctx, id) {
  const auth = ctx && ctx.auth;
  if (!auth) return jsonError(401, "未鉴权");
  if (!id) return jsonError(400, "缺少会话 id");
  if (!env.DB) return jsonError(503, "数据库未配置");

  try {
    const row = await env.DB.prepare(
      `SELECT * FROM conversations WHERE id = ?1 AND user_id = ?2`
    )
      .bind(id, auth.userId)
      .first();
    if (!row) return jsonError(404, "会话不存在");
    return jsonOk({ conversation: row });
  } catch (err) {
    return jsonError(500, "查询会话失败: " + (err && err.message));
  }
}

/**
 * PATCH /conversations/:id - 更新会话（标题/置顶/system prompt 等）
 * body: { title?, isPinned?, systemPrompt?, orderField? }
 */
export async function handleUpdateConversation(request, env, ctx, id) {
  const auth = ctx && ctx.auth;
  if (!auth) return jsonError(401, "未鉴权");
  if (!id) return jsonError(400, "缺少会话 id");
  if (!env.DB) return jsonError(503, "数据库未配置");

  let body;
  try {
    body = await request.json();
  } catch (_) {
    return jsonError(400, "请求体不是合法 JSON");
  }

  // 仅允许更新这些字段，避免 SQL 注入
  const fields = [];
  const values = [];
  if (typeof body.title === "string") {
    fields.push("title = ?");
    values.push(body.title);
  }
  if (typeof body.isPinned === "number" || typeof body.isPinned === "boolean") {
    fields.push("is_pinned = ?");
    values.push(body.isPinned ? 1 : 0);
  }
  if (typeof body.systemPrompt === "string") {
    fields.push("system_prompt = ?");
    values.push(body.systemPrompt);
  }
  if (typeof body.orderField === "number") {
    fields.push("order_field = ?");
    values.push(body.orderField);
  }
  if (fields.length === 0) {
    return jsonError(400, "没有可更新的字段");
  }

  fields.push("updated_at = ?");
  values.push(Date.now());
  values.push(id, auth.userId);

  try {
    const { changes } = await env.DB.prepare(
      `UPDATE conversations SET ${fields.join(", ")} WHERE id = ? AND user_id = ?`
    )
      .bind(...values)
      .run();
    if (changes === 0) return jsonError(404, "会话不存在或无变更");
    const row = await env.DB.prepare(
      `SELECT * FROM conversations WHERE id = ?1 AND user_id = ?2`
    )
      .bind(id, auth.userId)
      .first();
    return jsonOk({ conversation: row });
  } catch (err) {
    return jsonError(500, "更新会话失败: " + (err && err.message));
  }
}

/**
 * DELETE /conversations/:id - 删除会话（级联删除其下消息）
 */
export async function handleDeleteConversation(request, env, ctx, id) {
  const auth = ctx && ctx.auth;
  if (!auth) return jsonError(401, "未鉴权");
  if (!id) return jsonError(400, "缺少会话 id");
  if (!env.DB) return jsonError(503, "数据库未配置");

  try {
    // 先校验会话属于当前用户，避免越权删除他人消息（IDOR）
    const conv = await env.DB.prepare(
      `SELECT id FROM conversations WHERE id = ?1 AND user_id = ?2`
    )
      .bind(id, auth.userId)
      .first();
    if (!conv) return jsonError(404, "会话不存在");

    // 已确认归属，删除消息（外键级联在 D1 需显式开启 PRAGMA，这里手动删更稳妥）
    await env.DB.prepare(`DELETE FROM messages WHERE conversation_id = ?1`).bind(id).run();
    const { changes } = await env.DB.prepare(
      `DELETE FROM conversations WHERE id = ?1 AND user_id = ?2`
    )
      .bind(id, auth.userId)
      .run();
    if (changes === 0) return jsonError(404, "会话不存在");
    return jsonOk({ deleted: true, id });
  } catch (err) {
    return jsonError(500, "删除会话失败: " + (err && err.message));
  }
}

/// 生成 UUID（Workers runtime 支持 crypto.randomUUID）
function genId() {
  if (typeof crypto !== "undefined" && crypto.randomUUID) {
    return crypto.randomUUID();
  }
  return "id-" + Date.now().toString(36) + "-" + Math.random().toString(36).slice(2, 10);
}

/// 构造 JSON 成功响应
function jsonOk(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
