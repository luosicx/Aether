/**
 * 限流中间件：令牌桶限流器（WASM，Rust aether-core token-bucket）
 *
 * 基于 Cloudflare Workers 内存 Map 存储 per-userId RateLimiter 实例。
 * 非全局持久化；不同 Worker 实例间不共享。
 * 生产环境如需精确限流，建议改用 Durable Objects 或 KV 计数器。
 *
 * 默认每 userId 每分钟 60 次（capacity=60, refillRate=1/sec）。
 */

// RateLimiter WASM 懒加载单例；WASM 产物不可用时降级纯 JS 令牌桶（算法等价）
let _RateLimiterCtor = null;
let _wasmLoadFailed = false;
async function getRateLimiterCtor() {
  if (_RateLimiterCtor) return _RateLimiterCtor;
  if (_wasmLoadFailed) return null;
  try {
    const mod = await import("../../wasm/aether_sse.js");
    await mod.default();
    _RateLimiterCtor = mod.RateLimiter;
  } catch (err) {
    console.error("ratelimit: WASM 不可用，降级纯 JS 令牌桶:", err && err.message);
    _wasmLoadFailed = true;
  }
  return _RateLimiterCtor;
}

/**
 * 纯 JS 令牌桶（WASM 不可用时的等价降级实现）
 * 接口与 WASM RateLimiter 对齐：new (capacity, refillRate, nowMs) / acquire(n, nowMs) / availableTokens(nowMs)
 */
class JSRateLimiter {
  constructor(capacity, refillRate, now) {
    this.capacity = capacity;
    this.tokens = capacity;
    this.refillRate = refillRate; // tokens/sec
    this.last = now;
  }

  refill(now) {
    const dt = Math.max(0, now - this.last) / 1000;
    this.tokens = Math.min(this.capacity, this.tokens + dt * this.refillRate);
    this.last = now;
  }

  acquire(n, now) {
    this.refill(now);
    if (this.tokens >= n) {
      this.tokens -= n;
      return 0;
    }
    return (n - this.tokens) / this.refillRate; // 需等待的秒数
  }

  availableTokens(now) {
    this.refill(now);
    return this.tokens;
  }
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
    bucket = new (RateLimiter || JSRateLimiter)(limit, limit / 60.0, now);
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
