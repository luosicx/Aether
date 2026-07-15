/**
 * 长期记忆路由：记忆的增删查搜
 *
 * 所有端点需要鉴权（X-BFF-Token），数据按 user_id 隔离。
 * 路由函数签名统一 (request, env, ctx)，ctx 可选。
 */

import { jsonError } from "../lib/llm.js";
import { fetchRelevantMemories, createMemory } from "../lib/memory.js";

/**
 * GET /memory - 列出当前用户的记忆
 * query: ?limit=50&offset=0&category=xxx
 */
export async function handleListMemory(request, env, ctx) {
  const auth = ctx && ctx.auth;
  if (!auth) return jsonError(401, "未鉴权");
  if (!env.DB) return jsonError(503, "数据库未配置");

  const url = new URL(request.url);
  const limit = Math.min(parseInt(url.searchParams.get("limit") || "50", 10), 200);
  const offset = parseInt(url.searchParams.get("offset") || "0", 10);
  const category = url.searchParams.get("category");

  try {
    let sql, binds;
    if (category) {
      sql = `SELECT * FROM memories WHERE user_id = ?1 AND category = ?2 ORDER BY importance DESC, created_at DESC LIMIT ?3 OFFSET ?4`;
      binds = [auth.userId, category, limit, offset];
    } else {
      sql = `SELECT * FROM memories WHERE user_id = ?1 ORDER BY importance DESC, created_at DESC LIMIT ?2 OFFSET ?3`;
      binds = [auth.userId, limit, offset];
    }
    const { results } = await env.DB.prepare(sql).bind(...binds).all();
    return jsonOk({ memories: results || [] });
  } catch (err) {
    return jsonError(500, "查询记忆失败: " + (err && err.message));
  }
}

/**
 * POST /memory - 创建一条记忆
 * body: { content, category?, importance?, sourceConversationId? }
 */
export async function handleCreateMemory(request, env, ctx) {
  const auth = ctx && ctx.auth;
  if (!auth) return jsonError(401, "未鉴权");
  if (!env.DB) return jsonError(503, "数据库未配置");

  let body;
  try {
    body = await request.json();
  } catch (_) {
    return jsonError(400, "请求体不是合法 JSON");
  }
  if (!body || !body.content) {
    return jsonError(400, "content 不能为空");
  }

  const id = genId();
  const memory = {
    id,
    user_id: auth.userId,
    content: body.content,
    category: body.category || null,
    importance: typeof body.importance === "number" ? body.importance : 0.5,
    source_conversation_id: body.sourceConversationId || null,
    created_at: Date.now(),
  };

  const ok = await createMemory(env, memory);
  if (!ok) return jsonError(500, "创建记忆失败");
  return jsonOk({ memory }, 201);
}

/**
 * POST /memory/search - 搜索记忆（文本匹配）
 * body: { query, limit? }
 */
export async function handleSearchMemory(request, env, ctx) {
  const auth = ctx && ctx.auth;
  if (!auth) return jsonError(401, "未鉴权");

  let body;
  try {
    body = await request.json();
  } catch (_) {
    return jsonError(400, "请求体不是合法 JSON");
  }
  if (!body || !body.query) {
    return jsonError(400, "query 不能为空");
  }

  const limit = typeof body.limit === "number" ? body.limit : 5;
  const memories = await fetchRelevantMemories(env, auth.userId, body.query, limit);
  return jsonOk({ memories, query: body.query });
}

/**
 * DELETE /memory/:id - 删除一条记忆
 */
export async function handleDeleteMemory(request, env, ctx, id) {
  const auth = ctx && ctx.auth;
  if (!auth) return jsonError(401, "未鉴权");
  if (!id) return jsonError(400, "缺少 id");
  if (!env.DB) return jsonError(503, "数据库未配置");

  try {
    const { changes } = await env.DB.prepare(
      `DELETE FROM memories WHERE id = ?1 AND user_id = ?2`
    )
      .bind(id, auth.userId)
      .run();
    if (changes === 0) return jsonError(404, "记忆不存在或无权删除");
    return jsonOk({ deleted: true, id });
  } catch (err) {
    return jsonError(500, "删除记忆失败: " + (err && err.message));
  }
}

/// 生成 UUID
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
