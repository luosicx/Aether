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
  if (!ctx || !ctx.auth) return jsonError(401, "未鉴权");
  const db = ctx.db;
  if (!db) return jsonError(503, "数据库未配置");

  const url = new URL(request.url);
  const limit = Math.min(parseInt(url.searchParams.get("limit") || "50", 10), 200);
  const offset = parseInt(url.searchParams.get("offset") || "0", 10);
  const pinnedOnly = url.searchParams.get("pinned") === "1";

  try {
    const conversations = await db.listConversations({ limit, offset, pinnedOnly });
    return jsonOk({ conversations });
  } catch (err) {
    return jsonError(500, "查询会话失败: " + (err && err.message));
  }
}

/**
 * POST /conversations - 创建会话
 * body: { title?, systemPrompt?, parentId? }
 */
export async function handleCreateConversation(request, env, ctx) {
  if (!ctx || !ctx.auth) return jsonError(401, "未鉴权");
  const db = ctx.db;
  if (!db) return jsonError(503, "数据库未配置");

  let body;
  try {
    body = await request.json();
  } catch (_) {
    return jsonError(400, "请求体不是合法 JSON");
  }

  try {
    const conversation = await db.createConversation({
      title: (body && body.title) || "新会话",
      systemPrompt: (body && body.systemPrompt) || "你是一个有帮助的AI助手。",
      parentId: (body && body.parentId) || null,
    });
    return jsonOk({ conversation }, 201);
  } catch (err) {
    return jsonError(500, "创建会话失败: " + (err && err.message));
  }
}

/**
 * GET /conversations/:id - 获取单个会话
 */
export async function handleGetConversation(request, env, ctx, id) {
  if (!ctx || !ctx.auth) return jsonError(401, "未鉴权");
  const db = ctx.db;
  if (!id) return jsonError(400, "缺少会话 id");
  if (!db) return jsonError(503, "数据库未配置");

  try {
    const row = await db.getConversation(id);
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
  if (!ctx || !ctx.auth) return jsonError(401, "未鉴权");
  const db = ctx.db;
  if (!id) return jsonError(400, "缺少会话 id");
  if (!db) return jsonError(503, "数据库未配置");

  let body;
  try {
    body = await request.json();
  } catch (_) {
    return jsonError(400, "请求体不是合法 JSON");
  }

  try {
    const { empty, changed, conversation } = await db.updateConversation(id, body || {});
    if (empty) return jsonError(400, "没有可更新的字段");
    if (!changed) return jsonError(404, "会话不存在或无变更");
    return jsonOk({ conversation });
  } catch (err) {
    return jsonError(500, "更新会话失败: " + (err && err.message));
  }
}

/**
 * DELETE /conversations/:id - 删除会话（级联删除其下消息）
 */
export async function handleDeleteConversation(request, env, ctx, id) {
  if (!ctx || !ctx.auth) return jsonError(401, "未鉴权");
  const db = ctx.db;
  if (!id) return jsonError(400, "缺少会话 id");
  if (!db) return jsonError(503, "数据库未配置");

  try {
    const deleted = await db.deleteConversation(id);
    if (!deleted) return jsonError(404, "会话不存在");
    return jsonOk({ deleted: true, id });
  } catch (err) {
    return jsonError(500, "删除会话失败: " + (err && err.message));
  }
}

/// 构造 JSON 成功响应
function jsonOk(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
