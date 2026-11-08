/**
 * 长期记忆路由：记忆的增删查搜
 *
 * 所有端点需要鉴权（X-BFF-Token）。数据访问统一经 ctx.db（tenant-db 访问器），
 * user_id 由访问器绑定，路由层不直接持有 env.DB。
 * 路由函数签名统一 (request, env, ctx)，ctx 可选。
 */

import { jsonError } from "../lib/llm.js";

/**
 * GET /memory - 列出当前用户的记忆
 * query: ?limit=50&offset=0&category=xxx
 */
export async function handleListMemory(request, env, ctx) {
  if (!ctx || !ctx.auth) return jsonError(401, "未鉴权");
  const db = ctx.db;
  if (!db) return jsonError(503, "数据库未配置");

  const url = new URL(request.url);
  const limit = Math.min(parseInt(url.searchParams.get("limit") || "50", 10), 200);
  const offset = parseInt(url.searchParams.get("offset") || "0", 10);
  const category = url.searchParams.get("category");

  try {
    const memories = await db.listMemories({ limit, offset, category });
    return jsonOk({ memories });
  } catch (err) {
    return jsonError(500, "查询记忆失败: " + (err && err.message));
  }
}

/**
 * POST /memory - 创建一条记忆
 * body: { content, category?, importance?, sourceConversationId? }
 */
export async function handleCreateMemory(request, env, ctx) {
  if (!ctx || !ctx.auth) return jsonError(401, "未鉴权");
  const db = ctx.db;
  if (!db) return jsonError(503, "数据库未配置");

  let body;
  try {
    body = await request.json();
  } catch (_) {
    return jsonError(400, "请求体不是合法 JSON");
  }
  if (!body || !body.content) {
    return jsonError(400, "content 不能为空");
  }

  try {
    const memory = await db.createMemory({
      content: body.content,
      category: body.category || null,
      importance: typeof body.importance === "number" ? body.importance : 0.5,
      sourceConversationId: body.sourceConversationId || null,
    });
    return jsonOk({ memory }, 201);
  } catch (err) {
    console.error("创建记忆失败:", err && err.message);
    return jsonError(500, "创建记忆失败");
  }
}

/**
 * POST /memory/search - 搜索记忆（文本匹配）
 * body: { query, limit? }
 */
export async function handleSearchMemory(request, env, ctx) {
  if (!ctx || !ctx.auth) return jsonError(401, "未鉴权");

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
  // 无 DB 时降级为空结果，不阻断检索接口
  const memories = ctx.db ? await ctx.db.searchMemories(body.query, limit) : [];
  return jsonOk({ memories, query: body.query });
}

/**
 * DELETE /memory/:id - 删除一条记忆
 */
export async function handleDeleteMemory(request, env, ctx, id) {
  if (!ctx || !ctx.auth) return jsonError(401, "未鉴权");
  const db = ctx.db;
  if (!id) return jsonError(400, "缺少 id");
  if (!db) return jsonError(503, "数据库未配置");

  try {
    const deleted = await db.deleteMemory(id);
    if (!deleted) return jsonError(404, "记忆不存在或无权删除");
    return jsonOk({ deleted: true, id });
  } catch (err) {
    console.error("删除记忆失败:", err && err.message);
    return jsonError(500, "删除记忆失败");
  }
}

/// 构造 JSON 成功响应
function jsonOk(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
