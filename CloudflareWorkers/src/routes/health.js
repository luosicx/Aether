/**
 * 健康摘要路由：上报与查询每日健康数据
 *
 * 所有端点需要鉴权（X-BFF-Token）。数据访问统一经 ctx.db（tenant-db 访问器），
 * user_id 由访问器绑定，路由层不直接持有 env.DB。
 * 路由函数签名统一 (request, env, ctx)，ctx 可选。
 */

import { jsonError } from "../lib/llm.js";

/**
 * POST /health/summary - 上报某日健康摘要（按 user_id + date upsert）
 * body: { date, steps?, sleepHours?, restingHeartRate? }
 *   - date: YYYY-MM-DD
 */
export async function handleUploadHealthSummary(request, env, ctx) {
  if (!ctx || !ctx.auth) return jsonError(401, "未鉴权");
  const db = ctx.db;
  if (!db) return jsonError(503, "数据库未配置");

  let body;
  try {
    body = await request.json();
  } catch (_) {
    return jsonError(400, "请求体不是合法 JSON");
  }
  if (!body || !body.date || !/^\d{4}-\d{2}-\d{2}$/.test(body.date)) {
    return jsonError(400, "date 必须为 YYYY-MM-DD 格式");
  }

  const steps = typeof body.steps === "number" ? body.steps : null;
  const sleepHours = typeof body.sleepHours === "number" ? body.sleepHours : null;
  const restingHeartRate =
    typeof body.restingHeartRate === "number" ? body.restingHeartRate : null;

  try {
    // 与 GET /health/summary/{date} 保持同一 envelope + snake_case 字段
    const summary = await db.upsertHealthSummary(body.date, {
      steps,
      sleepHours,
      restingHeartRate,
    });
    return jsonOk({ summary });
  } catch (err) {
    return jsonError(500, "上报健康摘要失败: " + (err && err.message));
  }
}

/**
 * GET /health/summary/:date - 获取某日健康摘要
 */
export async function handleGetHealthSummary(request, env, ctx, date) {
  if (!ctx || !ctx.auth) return jsonError(401, "未鉴权");
  const db = ctx.db;
  if (!date || !/^\d{4}-\d{2}-\d{2}$/.test(date)) {
    return jsonError(400, "date 必须为 YYYY-MM-DD 格式");
  }
  if (!db) return jsonError(503, "数据库未配置");

  try {
    const row = await db.getHealthSummary(date);
    if (!row) return jsonError(404, "该日期无健康摘要");
    return jsonOk({ summary: row });
  } catch (err) {
    console.error("查询健康摘要失败:", err && err.message);
    return jsonError(500, "查询健康摘要失败");
  }
}

/// 构造 JSON 成功响应
function jsonOk(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
