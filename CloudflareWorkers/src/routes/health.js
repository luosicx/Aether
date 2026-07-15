/**
 * 健康摘要路由：上报与查询每日健康数据
 *
 * 所有端点需要鉴权（X-BFF-Token），数据按 user_id 隔离。
 * 路由函数签名统一 (request, env, ctx)，ctx 可选。
 */

import { jsonError } from "../lib/llm.js";

/**
 * POST /health/summary - 上报某日健康摘要（按 user_id + date upsert）
 * body: { date, steps?, sleepHours?, restingHeartRate? }
 *   - date: YYYY-MM-DD
 */
export async function handleUploadHealthSummary(request, env, ctx) {
  const auth = ctx && ctx.auth;
  if (!auth) return jsonError(401, "未鉴权");
  if (!env.DB) return jsonError(503, "数据库未配置");

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
    // D1 支持 INSERT OR REPLACE（SQLite 语法）
    await env.DB.prepare(
      `INSERT OR REPLACE INTO health_summaries (user_id, date, steps, sleep_hours, resting_heart_rate)
       VALUES (?1, ?2, ?3, ?4, ?5)`
    )
      .bind(auth.userId, body.date, steps, sleepHours, restingHeartRate)
      .run();

    return jsonOk({
      userId: auth.userId,
      date: body.date,
      steps,
      sleepHours,
      restingHeartRate,
    });
  } catch (err) {
    return jsonError(500, "上报健康摘要失败: " + (err && err.message));
  }
}

/**
 * GET /health/summary/:date - 获取某日健康摘要
 */
export async function handleGetHealthSummary(request, env, ctx, date) {
  const auth = ctx && ctx.auth;
  if (!auth) return jsonError(401, "未鉴权");
  if (!date || !/^\d{4}-\d{2}-\d{2}$/.test(date)) {
    return jsonError(400, "date 必须为 YYYY-MM-DD 格式");
  }
  if (!env.DB) return jsonError(503, "数据库未配置");

  try {
    const row = await env.DB.prepare(
      `SELECT * FROM health_summaries WHERE user_id = ?1 AND date = ?2`
    )
      .bind(auth.userId, date)
      .first();
    if (!row) return jsonError(404, "该日期无健康摘要");
    return jsonOk({ summary: row });
  } catch (err) {
    return jsonError(500, "查询健康摘要失败: " + (err && err.message));
  }
}

/// 构造 JSON 成功响应
function jsonOk(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
