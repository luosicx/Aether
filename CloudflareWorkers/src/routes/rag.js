/**
 * RAG 路由：文档检索与上传
 *
 * 所有端点需要鉴权（X-BFF-Token）。数据访问统一经 ctx.db（tenant-db 访问器），
 * user_id 由访问器绑定，路由层不直接持有 env.DB。
 * 路由函数签名统一 (request, env, ctx)，ctx 可选。
 */

import { jsonError } from "../lib/llm.js";

/**
 * POST /rag/search - 检索与查询相关的文档分块
 * body: { query, limit? }
 */
export async function handleSearchDocuments(request, env, ctx) {
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

  const limit = typeof body.limit === "number" ? body.limit : 3;
  // 无 DB 时降级为空结果，不阻断检索接口
  const chunks = ctx.db ? await ctx.db.searchChunks(body.query, limit) : [];
  return jsonOk({ chunks, query: body.query });
}

/**
 * POST /rag/documents - 上传文档（含分块）
 * body: { title, content, source? }
 */
export async function handleUploadDocument(request, env, ctx) {
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

  const result = await db.createDocumentWithChunks({
    title: body.title,
    source: body.source,
    content: body.content,
  });

  if (!result) return jsonError(500, "上传文档失败");
  return jsonOk({ documentId: result.documentId, chunkCount: result.chunkCount }, 201);
}

/// 构造 JSON 成功响应
function jsonOk(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
