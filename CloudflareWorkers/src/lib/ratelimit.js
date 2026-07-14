/**
 * 限流中间件：内存计数器实现每分钟限流
 *
 * 与现有 worker.js 一致：基于单个 Worker 实例内存 Map，
 * 非全局持久化；不同实例间不共享。
 * 生产环境如需精确限流，建议改用 Durable Objects 或 KV 计数器。
 *
 * 默认每 userId 每分钟 60 次。
 */

// 内存计数器：userId -> { count, windowStart }
const rateLimitMap = new Map();

// 限流窗口（毫秒）
const WINDOW_MS = 60_000;

/**
 * 检查限流
 * @param {string} userId
 * @param {Object} env - 保留参数以便后续切换为 KV/Durable Objects 限流
 * @param {number} limit - 每分钟允许的请求数，默认 60
 * @returns {{allowed: boolean, retryAfter?: number, remaining?: number}}
 */
export function checkRateLimit(userId, env, limit = 60) {
  const now = Date.now();
  let entry = rateLimitMap.get(userId);
  if (!entry || now - entry.windowStart >= WINDOW_MS) {
    entry = { count: 0, windowStart: now };
    rateLimitMap.set(userId, entry);
  }
  entry.count += 1;

  if (entry.count > limit) {
    // 计算距窗口重置的剩余秒数（至少 1 秒）
    const retryAfter = Math.max(1, Math.ceil((WINDOW_MS - (now - entry.windowStart)) / 1000));
    return { allowed: false, retryAfter };
  }

  return { allowed: true, remaining: Math.max(0, limit - entry.count) };
}

/**
 * 限流失败响应构造（与现有 worker.js 429 格式对齐）
 * @param {number} retryAfter
 * @returns {Response}
 */
export function rateLimitResponse(retryAfter) {
  return new Response(JSON.stringify({ error: "rate limited" }), {
    status: 429,
    headers: {
      "Content-Type": "application/json",
      "Retry-After": String(retryAfter),
    },
  });
}
