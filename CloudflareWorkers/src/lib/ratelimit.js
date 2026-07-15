/**
 * 限流中间件：令牌桶限流器（WASM，Rust aether-core token-bucket）
 *
 * 基于 Cloudflare Workers 内存 Map 存储 per-userId RateLimiter 实例。
 * 非全局持久化；不同 Worker 实例间不共享。
 * 生产环境如需精确限流，建议改用 Durable Objects 或 KV 计数器。
 *
 * 默认每 userId 每分钟 60 次（capacity=60, refillRate=1/sec）。
 */

// RateLimiter WASM 懒加载单例
let _RateLimiterCtor = null;
async function getRateLimiterCtor() {
  if (_RateLimiterCtor) return _RateLimiterCtor;
  const mod = await import("../../wasm/aether_sse.js");
  await mod.default();
  _RateLimiterCtor = mod.RateLimiter;
  return _RateLimiterCtor;
}

// 内存计数器：userId -> RateLimiter 实例
const rateLimitMap = new Map();

/**
 * 检查限流（令牌桶算法）
 * @param {string} userId
 * @param {Object} env - 保留参数以便后续切换为 KV/Durable Objects 限流
 * @param {number} limit - 每分钟允许的请求数，默认 60
 * @returns {Promise<{allowed: boolean, retryAfter?: number, remaining?: number}>}
 */
export async function checkRateLimit(userId, env, limit = 60) {
  const now = Date.now();
  const RateLimiter = await getRateLimiterCtor();

  let bucket = rateLimitMap.get(userId);
  if (!bucket) {
    // capacity = limit, refillRate = limit / 60 tokens/sec
    bucket = new RateLimiter(limit, limit / 60.0, now);
    rateLimitMap.set(userId, bucket);
  }

  const retryAfter = bucket.acquire(1.0, now);
  if (retryAfter > 0) {
    return { allowed: false, retryAfter: Math.ceil(retryAfter) };
  }

  return { allowed: true, remaining: Math.floor(bucket.availableTokens(now)) };
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
